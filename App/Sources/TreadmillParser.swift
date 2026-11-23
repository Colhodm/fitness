import CoreGraphics
import Foundation

/// Numbers read off a treadmill console photo. Everything is optional; the user confirms before saving.
struct TreadmillReading: Equatable {
    var seconds: Int?
    var distance: Double?
    /// nil when the photo didn't say.
    var distanceIsKm: Bool?
    var calories: Int?
    var speed: Double?
}

enum TreadmillParser {
    /// One recognized line of text. `box` is normalized with the origin at the bottom left (Vision).
    struct Item {
        let text: String
        let box: CGRect
    }

    private enum Label { case time, distance, calories, speed, other }

    private static func label(_ t: String) -> Label? {
        let s = t.lowercased()
        if s.contains("pace") || s.contains("incline") || s.contains("heart") || s.contains("bpm") || s.contains("pulse") || s.contains("level") { return .other }
        if s.contains("speed") || s.contains("mph") || s.contains("km/h") || s.contains("kph") { return .speed }
        if s.contains("cal") { return .calories }
        if s.contains("dist") || s.range(of: #"\b(miles?|mi|km)\b"#, options: .regularExpression) != nil { return .distance }
        if s.contains("time") || s.contains("elapsed") || s.contains("duration") { return .time }
        return nil
    }

    static func clock(_ s: String) -> Int? {
        guard let m = s.range(of: #"\d{1,2}:\d{2}(:\d{2})?"#, options: .regularExpression) else { return nil }
        let parts = s[m].split(separator: ":").compactMap { Int($0) }
        return parts.count == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : parts[0] * 60 + parts[1]
    }

    static func number(_ s: String) -> Double? {
        guard !s.contains(":"), let m = s.range(of: #"\d+([.,]\d+)?"#, options: .regularExpression) else { return nil }
        return Double(s[m].replacingOccurrences(of: ",", with: "."))
    }

    static func parse(_ items: [Item]) -> TreadmillReading {
        var r = TreadmillReading()
        let all = items.map { $0.text.lowercased() }.joined(separator: " ")
        if all.range(of: #"\bkm\b|kilomet"#, options: .regularExpression) != nil, !all.contains("mi") { r.distanceIsKm = true }
        else if all.range(of: #"\b(mi|miles?|mph)\b"#, options: .regularExpression) != nil { r.distanceIsKm = false }

        func center(_ b: CGRect) -> CGPoint { CGPoint(x: b.midX, y: b.midY) }
        // The value for a label: on the same line, else the nearest numeric line (favouring below and right).
        func value(for item: Item, _ pick: (String) -> Double?) -> Double? {
            if let v = pick(item.text) { return v }
            let c = center(item.box)
            return items.filter { $0.text != item.text && pick($0.text) != nil && (label($0.text) == nil || pick($0.text) != nil && label($0.text) == label(item.text)) }
                .map { i -> (Double, Double) in
                    let p = center(i.box)
                    let dx = Double(p.x - c.x), dy = Double(c.y - p.y)
                    let d = (dx * dx + dy * dy).squareRoot() + (dy < -0.02 ? 0.15 : 0)
                    return (d, pick(i.text)!)
                }
                .filter { $0.0 < 0.45 }.min { $0.0 < $1.0 }?.1
        }
        let asNumber: (String) -> Double? = { number($0) }
        let asClock: (String) -> Double? = { clock($0).map(Double.init) }
        for item in items {
            switch label(item.text) {
            case .time: if r.seconds == nil { r.seconds = value(for: item, asClock).map { Int($0) } }
            case .distance: if r.distance == nil { r.distance = value(for: item, asNumber).flatMap { $0 > 0 && $0 < 60 ? $0 : nil } }
            case .calories: if r.calories == nil { r.calories = value(for: item, asNumber).flatMap { $0 >= 1 && $0 < 5000 ? Int($0) : nil } }
            case .speed: if r.speed == nil { r.speed = value(for: item, asNumber).flatMap { $0 > 0 && $0 < 30 ? $0 : nil } }
            default: break
            }
        }
        // Unlabeled fallbacks: the longest clock that isn't a pace, and a number written with a distance unit.
        if r.seconds == nil {
            r.seconds = items.filter { label($0.text) != .other }.compactMap { clock($0.text) }.max()
        }
        if r.distance == nil, let i = items.first(where: { $0.text.lowercased().range(of: #"\d([.,]\d+)?\s*(mi|km)\b"#, options: .regularExpression) != nil }) {
            r.distance = number(i.text)
        }
        return r
    }

    /// Walking if the belt speed or average pace is slower than about 4.5 mph (7.2 km/h).
    static func looksLikeWalk(_ r: TreadmillReading) -> Bool {
        let km = r.distanceIsKm == true
        if let s = r.speed { return s < (km ? 7.2 : 4.5) }
        if let d = r.distance, let t = r.seconds, d > 0, t > 0 { return d / (Double(t) / 3600) < (km ? 7.2 : 4.5) }
        return false
    }
}
