//
//  UtilitiesPolylineLeadArrow.swift
//  trucker easy app
//
//  Projects GPS onto the active route polyline and places a single "lead" point
//  a fixed distance ahead — used by Horizon Mapbox / MapKit surfaces.

import CoreLocation
import MapKit

enum PolylineLeadArrow {

    /// Snaps GPS onto the route polyline and returns on-line position + corridor bearing.
    static func snappedPosition(
        coords: [CLLocationCoordinate2D],
        user: CLLocation,
        anchorIndex: inout Int
    ) -> (coordinate: CLLocationCoordinate2D, bearingDegrees: Double)? {
        guard coords.count >= 2 else { return nil }

        let n = coords.count
        var start = max(0, min(anchorIndex, n - 2))
        if start > 0 { start = max(0, start - 24) }
        let end = min(n - 2, start + 120)

        var bestDist = Double.greatestFiniteMagnitude
        var bestPoint: CLLocationCoordinate2D?
        var bestBearing: Double = 0
        var bestSeg = start

        for i in start...end {
            let a = coords[i]
            let b = coords[i + 1]
            guard let proj = projectPoint(user.coordinate, segmentStart: a, segmentEnd: b) else { continue }
            if proj.distanceMeters < bestDist {
                bestDist = proj.distanceMeters
                bestPoint = proj.coordinate
                bestBearing = a.bearing(to: b)
                bestSeg = i
            }
        }

        if bestPoint == nil {
            let idx = closestVertexIndex(coords: coords, user: user, anchorIndex: &anchorIndex)
            let i = min(idx, n - 2)
            bestPoint = coords[i]
            bestBearing = coords[i].bearing(to: coords[i + 1])
            bestSeg = i
        }

        anchorIndex = bestSeg
        guard let pt = bestPoint else { return nil }
        return (pt, bestBearing)
    }

    static func snappedPosition(
        polyline: MKPolyline,
        user: CLLocation,
        anchorIndex: inout Int
    ) -> (coordinate: CLLocationCoordinate2D, bearingDegrees: Double)? {
        guard polyline.pointCount >= 2 else { return nil }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return snappedPosition(coords: coords, user: user, anchorIndex: &anchorIndex)
    }

    /// Point on the polyline ~`lookaheadMeters` ahead of the user's closest vertex, with segment bearing (degrees clockwise from north).
    static func lookaheadPoint(
        coords: [CLLocationCoordinate2D],
        user: CLLocation,
        lookaheadMeters: Double,
        anchorIndex: inout Int
    ) -> (coordinate: CLLocationCoordinate2D, bearingDegrees: Double)? {
        guard coords.count >= 2, lookaheadMeters > 5 else { return nil }
        let idx = closestVertexIndex(coords: coords, user: user, anchorIndex: &anchorIndex)
        return pointAheadOnPolyline(fromVertexIndex: idx, coords: coords, metersAhead: lookaheadMeters)
    }

    static func lookaheadPoint(
        polyline: MKPolyline,
        user: CLLocation,
        lookaheadMeters: Double,
        anchorIndex: inout Int
    ) -> (coordinate: CLLocationCoordinate2D, bearingDegrees: Double)? {
        guard polyline.pointCount >= 2 else { return nil }
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return lookaheadPoint(coords: coords, user: user, lookaheadMeters: lookaheadMeters, anchorIndex: &anchorIndex)
    }

    private static func closestVertexIndex(
        coords: [CLLocationCoordinate2D],
        user: CLLocation,
        anchorIndex: inout Int
    ) -> Int {
        let n = coords.count
        guard n >= 2 else { return 0 }

        func dist(_ i: Int) -> Double {
            let c = coords[i]
            return user.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        }

        var idx = min(max(anchorIndex, 0), n - 1)

        if dist(idx) > 220 {
            var best = 0
            var bestD = Double.greatestFiniteMagnitude
            let strideBy = max(1, min(n / 200, 72))
            var i = 0
            while i < n {
                let d = dist(i)
                if d < bestD {
                    bestD = d
                    best = i
                }
                i += strideBy
            }
            idx = best
        }

        while idx < n - 1 {
            if dist(idx + 1) < dist(idx) { idx += 1 } else { break }
        }
        while idx > 0 {
            if dist(idx - 1) < dist(idx) { idx -= 1 } else { break }
        }

        anchorIndex = idx
        return idx
    }

    private static func pointAheadOnPolyline(
        fromVertexIndex startIdx: Int,
        coords: [CLLocationCoordinate2D],
        metersAhead: Double
    ) -> (coordinate: CLLocationCoordinate2D, bearingDegrees: Double)? {
        var remaining = metersAhead
        var j = max(0, min(startIdx, coords.count - 2))

        while j < coords.count - 1 {
            let a = coords[j]
            let b = coords[j + 1]
            let segLen = a.distance(to: b)
            guard segLen > 0.25 else {
                j += 1
                continue
            }
            let bearing = a.bearing(to: b)
            if remaining <= segLen {
                let t = max(0, min(1, remaining / segLen))
                let lat = a.latitude + (b.latitude - a.latitude) * t
                let lon = a.longitude + (b.longitude - a.longitude) * t
                return (CLLocationCoordinate2D(latitude: lat, longitude: lon), bearing)
            }
            remaining -= segLen
            j += 1
        }

        guard coords.count >= 2 else { return nil }
        let a = coords[coords.count - 2]
        let b = coords[coords.count - 1]
        return (b, a.bearing(to: b))
    }

    private static func projectPoint(
        _ p: CLLocationCoordinate2D,
        segmentStart a: CLLocationCoordinate2D,
        segmentEnd b: CLLocationCoordinate2D
    ) -> (coordinate: CLLocationCoordinate2D, distanceMeters: Double)? {
        let ax = a.longitude, ay = a.latitude
        let bx = b.longitude, by = b.latitude
        let px = p.longitude, py = p.latitude
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-14 else {
            let d = CLLocation(latitude: py, longitude: px)
                .distance(from: CLLocation(latitude: ay, longitude: ax))
            return (a, d)
        }
        var t = ((px - ax) * dx + (py - ay) * dy) / len2
        t = max(0, min(1, t))
        let q = CLLocationCoordinate2D(latitude: ay + dy * t, longitude: ax + dx * t)
        let d = CLLocation(latitude: py, longitude: px)
            .distance(from: CLLocation(latitude: q.latitude, longitude: q.longitude))
        return (q, d)
    }
}
