//
//  NavigationEngine.swift
//  trucker easy app
//

import Foundation
import CoreLocation
import Observation


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

    /// When true, the UI should immediately dim/remove the old route polyline so we never show the
    /// real GPS position alongside an incompatible route while a reroute is in flight.
    var shouldDimOldRoute: Bool = false

    var onStepChanged: ((Int, RouteStep) -> Void)?
    var onNeedsReroute: (() async -> Void)?
    var onArrival: (() -> Void)?

    /// Language used for voice turn announcements — sync with app's current language
    var language: AppLanguage = .english
    /// Unidade de distância falada — "mi" (US/Canadá/México → pés/milhas) ou "km" (métrico → m/km).
    /// Sincronizado com `regionalSettings.currentRegion.distanceUnit`.
    var distanceUnit: String = "mi"

    // Trucks take wider turns and GPS can drift ±20m — use generous thresholds
    private let announcementDistances: [Double] = [800, 400, 100, 50]
    // Trucks drift more on wide roads; immediate reroutes feel like "the route changed by itself".
    private let offRouteThreshold: Double = 120
    private let arrivalThreshold: Double = 50    // 30m too tight — trucks need more stopping distance

    // MARK: Fast off-route tuning
    /// Beyond this the position is clearly on another road, not GPS drift — qualifies for fast reroute.
    private let hardOffRouteThreshold: Double = 60
    /// Confirm off-route within a few seconds (instead of waiting for long distances) when the
    /// vehicle is consistently outside the corridor AND moving away from the route.
    private let fastOffRouteSeconds: TimeInterval = 6
    /// Minimum GPS confidence required to trust the real position enough to recalculate.
    private let minConfidenceForReroute: Double = 0.55

    private var lastSpokenStepIndex: Int = -1
    private var lastLocation: CLLocation?
    private var offRouteStreak: Int = 0

    // MARK: Fast off-route / confidence state
    /// When the current off-route episode began (first reading past the corridor). nil = on route.
    private var offRouteSince: Date?
    /// Distance-to-route of the previous fix — lets us tell if the driver is diverging or recovering.
    private var lastDistanceToRoute: Double = 0
    /// Smoothed GPS confidence (0…1) from accuracy + speed + heading consistency.
    private var confidence: Double = 1
    private var lastHeadingForConfidence: Double = -1
    /// Furthest route vertex the driver has reached — used to detect a passed/missed maneuver.
    private var maxReachedRouteIndex: Int = 0

    /// In-memory ring of recent off-route episodes for later analysis (capped).
    private(set) var offRouteEvents: [OffRouteEvent] = []

    struct OffRouteEvent {
        let timestamp: Date
        let coordinate: CLLocationCoordinate2D
        let distanceToRouteMeters: Double
        let confidence: Double
        let reason: String
        /// Seconds from first off-route reading until reroute was requested.
        let secondsToReroute: TimeInterval
    }

    /// Incremental polyline search anchor — avoids scanning thousands of coordinates every GPS tick (main-thread jank).
    private var lastClosestCoordinateIndex: Int = 0

    /// Prefix distance along polyline to each vertex — built once per route so ETA updates stay O(1) per GPS tick.
    private var vertexDistanceFromStart: [Double] = []

    /// Cumulative road distance from the route start to the END of each step (Valhalla step lengths),
    /// built once per route. Lets distance-to-next-turn count down smoothly and accurately instead of
    /// the old uniform-density index estimate (which drifted badly on compressed/uneven polylines).
    private var stepCumulativeEndDistance: [Double] = []

    var currentInstruction: String? {
        activeRoute?.steps[safe: currentStepIndex]?.instruction
    }

    func startNavigation(route: TruckRoute) {
        activeRoute = route
        currentStepIndex = 0
        state = .navigating
        lastSpokenStepIndex = -1
        isOffRoute = false
        shouldDimOldRoute = false
        offRouteStreak = 0
        offRouteSince = nil
        lastDistanceToRoute = 0
        confidence = 1
        lastHeadingForConfidence = -1
        maxReachedRouteIndex = 0
        lastClosestCoordinateIndex = 0
        vertexDistanceFromStart = Self.computePrefixDistances(route.coordinates)
        var stepAcc = 0.0
        stepCumulativeEndDistance = route.steps.map { stepAcc += $0.distanceMeters; return stepAcc }

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
        shouldDimOldRoute = false
        offRouteStreak = 0
        offRouteSince = nil
        lastDistanceToRoute = 0
        confidence = 1
        lastHeadingForConfidence = -1
        maxReachedRouteIndex = 0
        lastClosestCoordinateIndex = 0
        vertexDistanceFromStart = []
        stepCumulativeEndDistance = []
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
        if let step = route.steps[safe: currentStepIndex] {
            onStepChanged?(currentStepIndex, step)
        }
    }

    #if DEBUG
    /// Issue 1 (teste de estrada): rastreia regressões do índice mais-próximo — a assinatura
    /// do "tremor" de manobra. Só DEBUG; não afeta release.
    private var lastLoggedClosestIndex = -1
    /// Telemetria de "milhas erradas": loga, a cada manobra, a distância Valhalla vs a calculada,
    /// pra isolar onde a milha diverge no próximo road test (sem mudar comportamento).
    private var lastLoggedMileageStep = -1
    #endif

    func updateLocation(_ location: CLLocation) {
        guard state == .navigating || state == .rerouting else { return }
        guard let route = activeRoute, !route.coordinates.isEmpty else { return }

        lastLocation = location

        if let lastCoord = route.coordinates.last {
            let destination = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            let nearDest = location.distance(from: destination) < arrivalThreshold
            // Anti-falso-positivo: só declara "chegou" se já percorreu ~80% da rota (por índice) E
            // está a <50m do fim. Antes bastava estar a 50m do último ponto → disparava "chegou" cedo
            // quando a rota passava perto do destino no meio/início. Agora exige progresso REAL.
            let progressedToEnd = maxReachedRouteIndex >= Int(Double(route.coordinates.count) * 0.8)
            if nearDest, progressedToEnd {
                handleArrival()
                return
            }
            #if DEBUG
            if nearDest, !progressedToEnd {
                print("[Navigation] ⚠️ perto do destino mas só \(maxReachedRouteIndex)/\(route.coordinates.count) percorrido — NÃO declarou chegada (anti-falso-positivo)")
            }
            #endif
        }

        let (closestPoint, closestIndex) = findClosestPointOnRoute(to: location, route: route)
        let distanceToRoute = location.distance(from: closestPoint)

        // Update GPS confidence (accuracy + speed + heading consistency) before deciding anything.
        updateConfidence(location)
        // Track furthest point reached along the route so we can detect a missed maneuver.
        if closestIndex > maxReachedRouteIndex { maxReachedRouteIndex = closestIndex }

        if state == .navigating {
            evaluateOffRoute(location: location, route: route, distanceToRoute: distanceToRoute, routeIndex: closestIndex)
        } else if isOffRoute && distanceToRoute <= offRouteThreshold {
            // Back inside the corridor — clear off-route state.
            isOffRoute = false
            state = .navigating
            offRouteStreak = 0
            offRouteSince = nil
        }

        lastDistanceToRoute = distanceToRoute

        let nextTurnDistance = calculateDistanceToNextStep(from: location, route: route, startIndex: closestIndex)
        distanceToNextStep = nextTurnDistance

        #if DEBUG
        // Issue 1: loga quando o índice mais-próximo REGRIDE — sinal de pulo em interseção que faz
        // a distância-pra-manobra (e a instrução) tremer. Confirma a causa no próximo TestFlight.
        if lastLoggedClosestIndex >= 0, closestIndex < lastLoggedClosestIndex {
            print("[NavJitter] closestIdx \(lastLoggedClosestIndex)→\(closestIndex) "
                + "nextTurn=\(Int(nextTurnDistance))m step=\(currentStepIndex) "
                + "d2route=\(Int(distanceToRoute))m acc=\(Int(location.horizontalAccuracy))m")
        }
        lastLoggedClosestIndex = closestIndex
        #endif

        updateRemainingStats(from: location, route: route, routeIndex: closestIndex)
        checkAndAnnounceStep(distance: nextTurnDistance)

        #if DEBUG
        if currentStepIndex != lastLoggedMileageStep, let step = route.steps[safe: currentStepIndex] {
            lastLoggedMileageStep = currentStepIndex
            print("[NavMiles] step=\(currentStepIndex) '\(step.instruction)' "
                + "valhalla=\(String(format: "%.2f", step.distanceMeters / 1609.34))mi "
                + "calc2turn=\(String(format: "%.2f", nextTurnDistance / 1609.34))mi "
                + "remain=\(String(format: "%.1f", distanceRemaining / 1609.34))mi")
        }
        #endif

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

        // Issue 1 (tremor de manobra): em trevo/alça/retorno a rota passa perto de um trecho ANTERIOR.
        // Sem trava, o ponto mais-próximo regride pra esse trecho antigo e a distância-pra-manobra (e a
        // instrução falada) pula pra trás. Durante navegação ATIVA e DENTRO da rota, travamos a busca pra
        // frente: o índice não pode cair abaixo do ponto mais avançado já alcançado (−2 vértices p/ ruído
        // de GPS). Fora de rota / recalculando, a divergência é real → busca completa continua liberada.
        let forwardLock = (state == .navigating && !isOffRoute)
        let minIndexFloor = forwardLock ? min(max(0, maxReachedRouteIndex - 2), n - 1) : 0

        // Cold start or lost sync / large jump — coarse scan so we don't climb into a wrong local minimum.
        if lastClosestCoordinateIndex == 0 && anchorDist > 250 {
            idx = coarseClosestCoordinateIndex(to: location, coordinates: coords)
        } else if anchorDist > offRouteThreshold * 4 {
            idx = coarseClosestCoordinateIndex(to: location, coordinates: coords)
        }
        idx = max(idx, minIndexFloor)

        while idx < n - 1 {
            let d0 = location.distance(from: loc(at: idx))
            let d1 = location.distance(from: loc(at: idx + 1))
            if d1 < d0 { idx += 1 } else { break }
        }
        while idx > minIndexFloor {
            let d0 = location.distance(from: loc(at: idx))
            let dm = location.distance(from: loc(at: idx - 1))
            if dm < d0 { idx -= 1 } else { break }
        }

        let refineRadius = min(48, max(n / 4, 24))
        let low = max(minIndexFloor, idx - refineRadius)
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
        // Map-matching on-device: em vez do VÉRTICE mais próximo, projeta o GPS perpendicularmente no
        // SEGMENTO da via (entre vértices). Dá distância-à-rota exata (menos falso "fora de rota") e um
        // ponto suave que desliza ao longo da via. Sem rede, offline, custo zero — o que GPS sério faz
        // no loop ao vivo (Valhalla /trace_route seria rede por tick: errado aqui, ok só p/ correção offline).
        let snapped = bestProjectedPoint(location: location, coords: coords, around: bestIdx)
        return (snapped, bestIdx)
    }

    /// Projeta o ponto mais próximo entre os dois segmentos adjacentes ao vértice `idx`.
    private func bestProjectedPoint(location: CLLocation, coords: [CLLocationCoordinate2D], around idx: Int) -> CLLocation {
        let n = coords.count
        var best = coords[idx]
        var bestD = location.distance(from: CLLocation(latitude: best.latitude, longitude: best.longitude))
        func consider(_ a: Int, _ b: Int) {
            guard a >= 0, b < n, a != b else { return }
            let proj = Self.projectOntoSegment(location.coordinate, coords[a], coords[b])
            let d = location.distance(from: CLLocation(latitude: proj.latitude, longitude: proj.longitude))
            if d < bestD { bestD = d; best = proj }
        }
        consider(idx - 1, idx)
        consider(idx, idx + 1)
        return CLLocation(latitude: best.latitude, longitude: best.longitude)
    }

    /// Projeção perpendicular de P no segmento A→B (aprox. equirretangular local, precisa em escala de via).
    /// Retorna o ponto projetado, preso ao segmento (t ∈ [0,1]).
    private static func projectOntoSegment(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0 * cos(a.latitude * .pi / 180)
        guard mPerDegLon != 0 else { return a }
        let bx = (b.longitude - a.longitude) * mPerDegLon
        let by = (b.latitude  - a.latitude)  * mPerDegLat
        let px = (p.longitude - a.longitude) * mPerDegLon
        let py = (p.latitude  - a.latitude)  * mPerDegLat
        let segLenSq = bx * bx + by * by
        guard segLenSq > 0 else { return a }
        var t = (px * bx + py * by) / segLenSq
        t = min(1, max(0, t))
        return CLLocationCoordinate2D(
            latitude:  a.latitude  + (t * by) / mPerDegLat,
            longitude: a.longitude + (t * bx) / mPerDegLon
        )
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

    /// Road distance (m) to the next maneuver. Accurate path: cumulative distance to the end of the
    /// current step minus how far along the polyline the driver already is — so the banner counts
    /// down "0.5 mi → 0.4 → … → now" as the truck approaches the turn. Falls back to the old
    /// straight-line estimate only if the per-step / prefix tables aren't ready yet (transient).
    private func calculateDistanceToNextStep(from location: CLLocation, route: TruckRoute, startIndex: Int) -> Double {
        if currentStepIndex < stepCumulativeEndDistance.count,
           startIndex >= 0, startIndex < vertexDistanceFromStart.count {
            let turnAlongRoute = stepCumulativeEndDistance[currentStepIndex]
            let userAlongRoute = vertexDistanceFromStart[startIndex]
            return max(0, turnAlongRoute - userAlongRoute)
        }
        // Fallback (tables not built): straight-line to an estimated step-end coordinate.
        guard currentStepIndex < route.steps.count, route.distanceMeters > 0,
              !route.coordinates.isEmpty else { return 0 }
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

        // ETA: velocidade do GPS quando confiável (em movimento ≥2 m/s); senão a média PLANEJADA
        // da rota (REAL, do Valhalla: distância/duração) — nunca um valor fixo chutado. Parado, o
        // ETA reflete o ritmo planejado da rota, não um "30 mph" inventado.
        let plannedAvgSpeed = route.durationSeconds > 0 ? route.distanceMeters / route.durationSeconds : 0
        let speed = location.speed >= 2.0 ? location.speed : plannedAvgSpeed
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

    // MARK: - GPS confidence

    /// Simple confidence score (0…1) blending horizontal accuracy, speed, and heading consistency.
    /// Low confidence = the fix may be a glitch, so we should NOT yank the driver off the route on it.
    private func updateConfidence(_ location: CLLocation) {
        // Accuracy: ≤10m → 1.0, ≥60m → ~0.0 (trucks need a clean fix before we trust "wrong road").
        let acc = location.horizontalAccuracy
        let accScore: Double = acc < 0 ? 0 : max(0, min(1, (60 - acc) / 50))

        // Speed: a moving vehicle gives a far more trustworthy position than a parked one.
        let speed = location.speed // m/s; negative when invalid
        let speedScore: Double = speed < 0 ? 0.4 : min(1, max(0.3, speed / 8))

        // Heading consistency: erratic heading jumps between fixes signal multipath / urban canyon.
        var headingScore = 1.0
        let course = location.course
        if course >= 0 {
            if lastHeadingForConfidence >= 0 {
                var delta = abs(course - lastHeadingForConfidence).truncatingRemainder(dividingBy: 360)
                if delta > 180 { delta = 360 - delta }
                headingScore = delta > 90 ? 0.4 : 1.0
            }
            lastHeadingForConfidence = course
        }

        let instant = (accScore * 0.55) + (speedScore * 0.25) + (headingScore * 0.20)
        // Smooth so a single noisy fix can't whipsaw the decision.
        confidence = (confidence * 0.5) + (instant * 0.5)
    }

    // MARK: - Off-route evaluation

    private func evaluateOffRoute(location: CLLocation, route: TruckRoute, distanceToRoute: Double, routeIndex: Int) {
        let inCorridor = distanceToRoute <= offRouteThreshold
        let diverging = distanceToRoute > lastDistanceToRoute + 1   // moving further from the route

        if inCorridor {
            // Comfortably inside the corridor — reset all off-route accumulators.
            offRouteStreak = 0
            offRouteSince = nil
            return
        }

        // Outside the corridor: start/continue the off-route clock.
        if offRouteSince == nil { offRouteSince = Date() }
        offRouteStreak += 1
        let elapsed = Date().timeIntervalSince(offRouteSince ?? Date())

        // SEGURANÇA — nunca deixar o driver perdido: muito longe da rota (>240m) por tempo
        // sustentado e vários fixes consecutivos NÃO é ruído de GPS, é desvio real. Recalcula
        // INDEPENDENTE da confiança; senão, com sinal fraco (cânion/área remota) a confiança fica
        // baixa e o reroute nunca dispararia — o motorista seguiria perdido sem rota nova.
        if distanceToRoute > offRouteThreshold * 2 && elapsed >= 12 && offRouteStreak >= 5 {
            requestReroute(reason: "safety_far_sustained", location: location, distanceToRoute: distanceToRoute, elapsed: elapsed)
            return
        }

        // Only act on positions we actually trust — otherwise wait for a cleaner fix.
        guard confidence >= minConfidenceForReroute else { return }

        // (1) Missed-exit / passed-maneuver: clearly off the road, past the upcoming maneuver, and
        //     diverging. Recalculate immediately instead of waiting for long distances.
        if distanceToRoute > hardOffRouteThreshold && diverging && hasPassedUpcomingManeuver(routeIndex: routeIndex, route: route) {
            requestReroute(reason: "missed_maneuver", location: location, distanceToRoute: distanceToRoute, elapsed: elapsed)
            return
        }

        // (2) Fast confirmation: consistently outside the corridor for a few seconds while diverging.
        if elapsed >= fastOffRouteSeconds && offRouteStreak >= 3 && diverging {
            requestReroute(reason: "fast_diverging", location: location, distanceToRoute: distanceToRoute, elapsed: elapsed)
            return
        }

        // (3) Conservative fallback: far past the legacy threshold and confirmed by several fixes.
        if distanceToRoute > offRouteThreshold && offRouteStreak >= 3 {
            requestReroute(reason: "threshold", location: location, distanceToRoute: distanceToRoute, elapsed: elapsed)
        }
    }

    /// True when the GPS has advanced past where the next maneuver point sits on the polyline —
    /// i.e. the driver drove past the turn they were supposed to take.
    private func hasPassedUpcomingManeuver(routeIndex: Int, route: TruckRoute) -> Bool {
        guard currentStepIndex < route.steps.count, route.distanceMeters > 0, route.coordinates.count > 1 else { return false }
        let stepDistance = route.steps[currentStepIndex].distanceMeters
        let coordsPerMeter = Double(route.coordinates.count) / route.distanceMeters
        let maneuverIndex = min(lastClosestCoordinateIndex + Int(stepDistance * coordsPerMeter), route.coordinates.count - 1)
        // We consider the maneuver "passed" once our furthest reached index is at/after it.
        return maxReachedRouteIndex >= maneuverIndex && routeIndex >= maneuverIndex
    }

    private func requestReroute(reason: String, location: CLLocation, distanceToRoute: Double, elapsed: TimeInterval) {
        logOffRouteEvent(reason: reason, location: location, distanceToRoute: distanceToRoute, secondsToReroute: elapsed)
        offRouteStreak = 0
        offRouteSince = nil
        handleOffRoute(reason: reason)
    }

    private func logOffRouteEvent(reason: String, location: CLLocation, distanceToRoute: Double, secondsToReroute: TimeInterval) {
        let event = OffRouteEvent(
            timestamp: Date(),
            coordinate: location.coordinate,
            distanceToRouteMeters: distanceToRoute,
            confidence: confidence,
            reason: reason,
            secondsToReroute: secondsToReroute
        )
        offRouteEvents.append(event)
        if offRouteEvents.count > 50 { offRouteEvents.removeFirst(offRouteEvents.count - 50) }

    }

    /// Called by the UI when a reroute request can't proceed right now (cooldown / missing destination).
    /// Returns to navigating so the off-route detector can re-arm and retry, and restores the route line.
    func cancelPendingReroute() {
        guard state == .rerouting else { return }
        isOffRoute = false
        shouldDimOldRoute = false
        state = .navigating
        offRouteStreak = 0
        offRouteSince = nil
    }

    private func handleOffRoute(reason: String) {
        guard !isOffRoute else { return }

        isOffRoute = true
        state = .rerouting
        // Tell the UI to drop the now-incompatible route immediately (no real-position + wrong-line mix).
        shouldDimOldRoute = true

        #if DEBUG
        print("[Navigation] ⚠️ Off-route (\(reason))! Requesting reroute...")
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
        // Métrico (Brasil/Europa/etc.) — m/km falados.
        if distanceUnit == "km" {
            if meters >= 1000 {
                return String(format: "%.1f kilometers", meters / 1000)
            }
            if meters >= 450 { return "500 meters" }
            let rounded = max(Int((meters / 10).rounded()) * 10, 10)
            return "\(rounded) meters"
        }

        // Imperial (US/Canadá/México) — pés/milhas falados (consistente com a UI em "mi").
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

        // < 1/4 milha: pés arredondados a 50 (natural na fala), nunca metros nos EUA.
        let feet = meters * 3.28084
        let rounded = max(Int((feet / 50).rounded()) * 50, 50)
        return "\(rounded) feet"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
