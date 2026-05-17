import Foundation

/// Currency formatting helpers. The currency code follows the user's
/// preference stored in `UserDefaults` (set from the Settings panel).
enum Money {
    /// User-selected currency code (default `EUR`).
    static var currencyCode: String {
        UserDefaults.standard.string(forKey: "vault.currencyCode") ?? "EUR"
    }

    static func format(_ value: Double, signed: Bool = false, fractionDigits: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits
        f.locale = Locale(identifier: "fr_FR")
        if signed {
            f.positivePrefix = "+ " + (f.currencySymbol ?? "")
            f.negativePrefix = "− " + (f.currencySymbol ?? "")
            return f.string(from: NSNumber(value: abs(value))) ?? "—"
        }
        return f.string(from: NSNumber(value: value)) ?? "—"
    }

    static func compact(_ value: Double) -> String {
        let abs = Swift.abs(value)
        let sign = value < 0 ? "−" : ""
        let symbol = currencySymbol
        switch abs {
        case 1_000_000...:
            return "\(sign)\(String(format: "%.1f", abs / 1_000_000)) M\(symbol)"
        case 1_000...:
            return "\(sign)\(String(format: "%.1f", abs / 1_000)) k\(symbol)"
        default:
            return "\(sign)\(Int(abs)) \(symbol)"
        }
    }

    static var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = Locale(identifier: "fr_FR")
        return f.currencySymbol ?? "€"
    }
}

/// Pre-configured French date formatters, kept as static singletons because
/// `DateFormatter` is expensive to instantiate.
enum DateFmt {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static let monthShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMM"
        return f
    }()
}

/// Percentage formatter used for ratios (savings rate, allocation share).
enum Pct {
    static func format(_ value: Double, fractionDigits: Int = 1) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.locale = Locale(identifier: "fr_FR")
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits
        return f.string(from: NSNumber(value: value)) ?? "—"
    }
}
