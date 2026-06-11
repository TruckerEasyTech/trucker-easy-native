//
//  NavigationEngine.swift
//  trucker easy app
//

import Foundation
import CoreLocation
import Observation

private func agentLogNavigationEngine(
    runId: String,
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: Any] = [:]
) {
    let payload: [String: Any] = [
        "sessionId": "ff95f6",
        "runId": runId,
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          var line = String(data: json, encoding: .utf8) else { return }
    line.append("\n")
    DeveloperDebugLog.appendNDJSONLine(line)
}

@Observable
@MainActor
final class NavigationEngine {
    enum State {
        case idle
        case navigating
        case rerouting
        case arrived
    }

    var state: State = .idle
    var activeRoute: TruckRoute?
    var currentStepIndex: Int = 0
    var distanceToNextStep: Double = 0
    var distanceRemaining: Double = 0
    var timeRemaining: TimeInterval = 0
    var eta: Date?
    var isOffRoute: Bool = false

    var onStepChanged: ((Int, RouteStep) -> Void)?
    var onNeedsReroute: (() async -> Void)?
    var onArrival: (() -> Void)?

    /// Language used for voice turn announcements — sync with app's current language
    var language: AppLanguage = .english

    // Trucks take wider turns and GPS can drift ±20m — use generous thresholds
    private let announcementDistances: [Double] = [800, 400, 100, 50]
    // Trucks drift more on wide roads; immediate reroutes feel like "the route changed by itself".
    private let offRouteThreshold: Double = 120
    private let arrivalThreshold: Double = 50    // 30m too tight — trucks need more stopping distance

    private var lastSpokenStepIndex: Int = -1
    private var lastLocation: CLLocation?
    private var offRouteStreak: Int = 0

    /// Incremental polyline search anchor — avoids scanning thousands of coordinates every GPS tick (main-thread jank).
    private var lastClosestCoordinateIndex: Int = 0

    /// Prefix distance along polyline to each vertex — built once per route so ETA updates stay O(1) per GPS tick.
    private var vertexDistanceFromStart: [Double] = []

    var currentInstruction: String? {
        activeRoute?.steps[safe: currentStepIndex]?.instruction
    }

    func startNavigation(route: TruckRoute) {
        activeRoute = route
        currentStepIndex = 0
        state = .navigating
        lastSpokenStepIndex = -1
        isOffRoute = false
        offRouteStreak = 0
        lastClosestCoordinateIndex = 0
        vertexDistanceFromStart = Self.computePrefixDistances(route.coordinates)

        if route.durationSeconds > 0 {
            eta = Date().addingTimeInterval(route.durationSeconds)
            timeRemaining = route.durationSeconds
        }
        distanceRemaining = route.distanceMeters

        #if DEBUG
        print("[Navigation] ✅ Started navigation to \(route.destinationName)")
        #endif
    }

    func stopNavigation() {
        state = .idle
        activeRoute = nil
        currentStepIndex = 0
        lastSpokenStepIndex = -1
        isOffRoute = false
        offRouteStreak = 0
        lastClosestCoordinateIndex = 0
        vertexDistanceFromStart = []
        eta = nil
        distanceToNextStep = 0
        distanceRemaining = 0
        timeRemaining = 0

        #if DEBUG
        print("[Navigation] ⏹️ Navigation stopped")
        #endif
    }

    /// Keep UI-driven step browsing consistent with engine state (prevents "snapping back" / weird reroutes).
    func syncStepIndexFromUI(_ newIndex: Int) {
        guard let route = activeRoute else { return }
        let maxIdx = max(route.steps.count - 1, 0)
        let clamped = min(max(newIndex, 0), maxIdx)
        guard clamped != currentStepIndex else { return }
        currentStepIndex = clamped
        lastSpokenStepIndex = -1
        agentLogNavigationEngine(
            runId: "post-fix",
            hypothesisId: "H5",
            location: "UtilitiesNavigationEngine.swift:syncStepIndexFromUI",
            message: "UI synced step index",
            data: [
                "newIndex": clamped,
                "steps": route.steps.count
            ]
        )
        if let step = route.steps[safe: currentStepIndex] {
            onStepChanged?(currentStepIndex, step)
        }
    }

    func updateLocation(_ location: CLLocation) {
        guard state == .navigating || state == .rerouting else { return }
        guard let route = activeRoute, !route.coordinates.isEmpty else { return }

        lastLocation = location

        if let lastCoord = route.coordinates.last {
            let destination = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            if location.distance(from: destination) < arrivalThreshold {
                handleArrival()
                return
            }
        }

        let (closestPoint, closestIndex) = findClosestPointOnRoute(to: location, route: route)
        let distanceToRoute = location.distance(from: closestPoint)

        if distanceToRoute > offRouteThreshold && state == .navigating {
            offRouteStreak += 1
            // Require a few consecutive GPS updates past threshold to avoid jitter reroutes.
            if offRouteStreak >= 3 {
                agentLogNavigationEngine(
                    runId: "post-fix",
                    hypothesisId: "H6",
                    location: "UtilitiesNavigationEngine.swift:updateLocation",
                    message: "Off-route confirmed; requesting reroute",
                    data: [
                        "distanceToRouteM": Int(distanceToRoute),
                        "thresholdM": Int(offRouteThreshold),
                        "streak": offRouteStreak
                    ]
                )
                handleOffRoute()
                offRouteStreak = 0
            }
        } else if isOffRoute && distanceToRoute <= offRouteThreshold {
            isOffRoute = false
            state = .navigating
            offRouteStreak = 0
        } else {
            offRouteStreak = 0
        }

        let nextTurnDistance = calculateDistanceToNextStep(from: location, route: route, startIndex: closestIndex)
        distanceToNextStep = nextTurnDistance

        updateRemainingStats(from: location, route: route, routeIndex: closestIndex)
        checkAndAnnounceStep(distance: nextTurnDistance)

        // Advance step at 20m — gives enough lead-in for trucks at highway speed
        if nextTurnDistance < 20 && currentStepIndex < route.steps.count - 1 {
            moveToNextStep()
        }
    }

    private func findClosestPointOnRoute(to location: CLLocation, route: TruckRoute) -> (CLLocation, Int) {
        let coords = route.coordinates
        guard let first = coords.first else {
            return (location, 0)
        }
        let n = coords.count
        if n == 1 {
            let l = CLLocation(latitude: first.latitude, longitude: first.longitude)
            return (l, 0)
        }

        func loc(at i: Int) -> CLLocation {
            let c = coords[i]
            return CLLocation(latitude: c.latitude, longitude: c.longitude)
        }

        var idx = min(max(lastClosestCoordinateIndex, 0), n - 1)
        let anchorDist = location.distance(from: loc(at: idx))

        // Cold start or lost sync / large jump — coarse scan so we don't climb into a wrong local minimum.
        if lastClosestCoordinateIndex == 0 && anchorDist > 250 {
            idx = coarseClosestCoordinateIndex(to: location, coordinates: coords)
        } else if anchorDist > offRouteThreshold * 4 {
            idx = coarseClosestCoordinateIndex(to: location, coordinates: coords)
        }

        while idx < n - 1 {
            let d0 = location.distance(from: loc(at: idx))
            let d1 = location.distance(from: loc(at: idx + 1))
            if d1 < d0 { idx += 1 } else { break }
        }
        while idx > 0 {
            let d0 = location.distance(from: loc(at: idx))
            let dm = location.distance(from: loc(at: idx - 1))
            if dm < d0 { idx -= 1 } else { break }
        }

        let refineRadius = min(48, max(n / 4, 24))
        let low = max(0, idx - refineRadius)
        let high = min(n - 1, idx + refineRadius)
        var bestIdx = idx
        var bestDist = location.distance(from: loc(at: idx))
        if low <= high {
            for i in low...high {
                let d = location.distance(from: loc(at: i))
                if d < bestDist {
                    bestDist = d
                    bestIdx = i
                }
            }
        }

        lastClosestCoordinateIndex = bestIdx
        let bc = coords[bestIdx]
        return (CLLocation(latitude: bc.latitude, longitude: bc.longitude), bestIdx)
    }

    /// ~O(n/stride) fallback when the vehicle is far from the last anchor or polyline is huge.
    private func coarseClosestCoordinateIndex(to location: CLLocation, coordinates: [CLLocationCoordinate2D]) -> Int {
        let n = coordinates.count
        guard n > 0 else { return 0 }
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        let strideBy = max(1, min(n / 250, 80))
        var i = 0
        while i < n {
            let c = coordinates[i]
            let d = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < bestD {
                bestD = d
                best = i
            }
            i += strideBy
        }
        return best
    }

    private static func computePrefixDistances(_ coords: [CLLocationCoordinate2D]) -> [Double] {
        guard coords.count >= 2 else { return coords.isEmpty ? [] : [0] }
        var out = Array(repeating: 0.0, count: coords.count)
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            out[i] = out[i - 1] + a.distance(from: b)
        }
        return out
    }

    private func calculateDistanceToNextStep(from location: CLLocation, route: TruckRoute, startIndex: Int) -> Double {
        guard currentStepIndex < route.steps.count, route.distanceMeters > 0 else { return 0 }

        let stepDistance = route.steps[currentStepIndex].distanceMeters
        let coordsPerMeter = Double(route.coordinates.count) / route.distanceMeters
        let estimatedIndex = min(startIndex + Int(stepDistance * coordsPerMeter), route.coordinates.count - 1)

        let stepCoordinate = route.coordinates[estimatedIndex]
        let stepLocation = CLLocation(latitude: stepCoordinate.latitude, longitude: stepCoordinate.longitude)
        return location.distance(from: stepLocation)
    }

    private func updateRemainingStats(from location: CLLocation, route: TruckRoute, routeIndex: Int) {
        guard route.coordinates.count > 1 else {
            distanceRemaining = 0
            timeRemaining = 0
            eta = nil
            return
        }

        let remaining: Double
        if vertexDistanceFromStart.count == route.coordinates.count {
            let i = min(max(routeIndex, 0), vertexDistanceFromStart.count - 1)
            let total = vertexDistanceFromStart.last ?? route.distanceMeters
            remaining = max(0, total - vertexDistanceFromStart[i])
        } else {
            var acc = 0.0
            let maxIdx = route.coordinates.count - 1
            if routeIndex < maxIdx {
                for index in routeIndex..<maxIdx {
                    let p1 = CLLocation(latitude: route.coordinates[index].latitude, longitude: route.coordinates[index].longitude)
                    let p2 = CLLocation(latitude: route.coordinates[index + 1].latitude, longitude: route.coordinates[index + 1].longitude)
                    acc += p1.distance(from: p2)
                }
            }
            remaining = acc
        }

        distanceRemaining = remaining

        let speed = max(location.speed, 13.4)
        if speed > 0 {
            timeRemaining = remaining / speed
            eta = Date().addingTimeInterval(timeRemaining)
        }
    }

    private func checkAndAnnounceStep(distance: Double) {
        guard currentStepIndex != lastSpokenStepIndex else { return }
        guard currentStepIndex < activeRoute?.steps.count ?? 0 else { return }

        // 100m window per threshold — at 60 mph (~27 m/s) that's ~3.7 seconds to catch the announcement
        for threshold in announcementDistances {
            if distance <= threshold && distance > threshold - 100 {
                announceStep()
                lastSpokenStepIndex = currentStepIndex
                break
            }
        }
    }

    private func announceStep() {
        guard let step = activeRoute?.steps[safe: currentStepIndex] else { return }

        let distanceText = formatDistance(distanceToNextStep)
        let instruction = step.instruction

        #if DEBUG
        print("[Navigation] 🔊 Announcing: In \(distanceText), \(instruction)")
        #endif

        VoiceNavigationManager.shared.announceStep(
            instructions: instruction,
            stepIndex: currentStepIndex,
            distanceText: distanceText,
            lang: language
        )

        onStepChanged?(currentStepIndex, step)
    }

    private func moveToNextStep() {
        currentStepIndex += 1
        lastSpokenStepIndex = -1

        if let step = activeRoute?.steps[safe: currentStepIndex] {
            onStepChanged?(currentStepIndex, step)
        }
    }

    private func handleOffRoute() {
        guard !isOffRoute else { return }

        isOffRoute = true
        state = .rerouting

        #if DEBUG
        print("[Navigation] ⚠️ User is off-route! Requesting reroute...")
        #endif

        Task {
            await onNeedsReroute?()
        }
    }

    private func handleArrival() {
        guard state == .navigating else { return }

        state = .arrived
        #if DEBUG
        print("[Navigation] 🎯 Arrived at destination!")
        #endif

        VoiceNavigationManager.shared.announceArrival(lang: language)
        onArrival?()
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1609 {
            let miles = meters / 1609.34
            return String(format: "%.1f miles", miles)
        }

        if meters >= 805 {
            return "half a mile"
        }

        if meters >= 402 {
            return "quarter mile"
        }

        return "\(Int(meters)) meters"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
