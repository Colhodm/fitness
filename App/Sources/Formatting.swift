import Foundation

enum Units {
    static let lbPerKg = 2.2046226218
    static let metersPerMile = 1609.344
    static let metersPerYard = 0.9144

    /// Convert stored pounds to the display unit.
    static func display(_ pounds: Double, _ unit: WeightUnit = AppSettings.shared.unit) -> Double {
        unit == .lb ? pounds : pounds / lbPerKg
    }

    /// Convert a display-unit value back to stored pounds.
    static func pounds(fromDisplay v: Double, _ unit: WeightUnit = AppSettings.shared.unit) -> Double {
        unit == .lb ? v : v * lbPerKg
    }

    static var unitLabel: String { AppSettings.shared.unit.rawValue }
    static var distanceLabel: String { AppSettings.shared.unit == .lb ? "yd" : "m" }
    static var runLabel: String { AppSettings.shared.unit == .lb ? "mi" : "km" }

    static func distanceDisplay(_ meters: Double) -> Double {
        AppSettings.shared.unit == .lb ? meters / metersPerYard : meters
    }
    static func meters(fromDisplay v: Double) -> Double {
        AppSettings.shared.unit == .lb ? v * metersPerYard : v
    }
    static func runDisplay(_ meters: Double) -> Double {
        AppSettings.shared.unit == .lb ? meters / metersPerMile : meters / 1000
    }
}

enum Fmt {
    /// "205", "182.4", "2.5"
    static func num(_ v: Double, maxDecimals: Int = 1) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = maxDecimals
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func fixed(_ v: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", v)
    }

    /// Weight in display units with no unit, rounded sensibly.
    static func w(_ pounds: Double) -> String {
        let v = Units.display(pounds)
        let rounded = AppSettings.shared.unit == .kg ? (v * 4).rounded() / 4 : (v * 10).rounded() / 10
        return num(rounded, maxDecimals: 2)
    }

    static func wu(_ pounds: Double) -> String { "\(w(pounds)) \(Units.unitLabel)" }

    static func signedW(_ pounds: Double) -> String {
        let s = w(abs(pounds))
        return pounds < 0 ? "−\(s)" : "+\(s)"
    }

    static func signed(_ v: Double, decimals: Int = 1) -> String {
        let s = fixed(abs(v), decimals)
        return v < 0 ? "−\(s)" : "+\(s)"
    }

    /// 130 -> "2:10"
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "1h 36m", "58 min"
    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)m"
    }

    static func dist(_ meters: Double) -> String { num(Units.distanceDisplay(meters).rounded(), maxDecimals: 0) }

    static func runDist(_ meters: Double, decimals: Int = 1) -> String { fixed(Units.runDisplay(meters), decimals) }

    /// seconds per mile/km -> "8:34"
    static func pace(seconds: Double, meters: Double) -> String {
        guard meters > 0 else { return "–" }
        let per = seconds / Units.runDisplay(meters)
        return clock(Int(per.rounded()))
    }

    static func date(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(format)
        return f.string(from: d)
    }

    /// "Tue" within the last week, otherwise "Nov 18".
    static func relativeDay(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day, days < 7 {
            return date(d, "EEE")
        }
        return date(d, "MMM d")
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    /// "Early Mar", "Mid Apr", "Late May"
    static func roughDate(_ d: Date) -> String {
        let day = Calendar.current.component(.day, from: d)
        let part = day <= 10 ? "Early" : day <= 20 ? "Mid" : "Late"
        return "\(part) \(date(d, "MMM"))"
    }

    static func weekRange(_ start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end)
        return "\(date(start, "MMM d")) – \(sameMonth ? date(end, "d") : date(end, "MMM d"))"
    }
}

extension Calendar {
    static var mondayFirst: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = .current
        return c
    }

    func startOfWeek(_ d: Date) -> Date {
        dateInterval(of: .weekOfYear, for: d)?.start ?? startOfDay(for: d)
    }
}
