import Foundation

/// Cadence at which a recurring transaction repeats.
enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .weekly:    return "Hebdomadaire"
        case .biweekly:  return "Bimensuel"
        case .monthly:   return "Mensuel"
        case .quarterly: return "Trimestriel"
        case .yearly:    return "Annuel"
        }
    }

    /// Conversion factor to monthly equivalents. Used by analytics to express
    /// any cadence as a comparable per-month amount.
    var monthlyFactor: Double {
        switch self {
        case .weekly:    return 52.0 / 12.0
        case .biweekly:  return 26.0 / 12.0
        case .monthly:   return 1.0
        case .quarterly: return 1.0 / 3.0
        case .yearly:    return 1.0 / 12.0
        }
    }

    /// Returns the next occurrence date after `date` following this cadence.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:    return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly:  return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly:   return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly: return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .yearly:    return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

/// A rule that generates `Transaction`s at a regular cadence.
///
/// The engine `RecurrenceEngine.applyDue(_:)` materialises every occurrence
/// whose `nextDate` is in the past into a concrete `Transaction` linked back
/// to this rule via `Transaction.sourceRecurrenceID`.
///
/// Forecasting (`ForecastEngine`) projects future net worth by **simulating**
/// these rules over a chosen horizon — no materialisation needed.
struct RecurringTransaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var amount: Double
    var kind: TransactionKind
    var frequency: RecurrenceFrequency

    /// First occurrence date — also the lower bound of any projection window.
    var startDate: Date

    /// Optional end date. After this date, no more occurrences are generated.
    var endDate: Date?

    /// Date of the **next** occurrence to be applied. Advanced by the engine
    /// each time an occurrence is materialised.
    var nextDate: Date

    /// Most recent date that was actually applied. Useful for diagnostics.
    var lastAppliedDate: Date?

    /// Toggle to temporarily pause a rule without deleting it.
    var isActive: Bool = true

    /// When true, the engine auto-creates the transaction at each occurrence.
    /// When false, the rule is informational only (forecasting still uses it).
    var autoApply: Bool = true

    var note: String = ""
    var accountID: UUID?
    var transferTargetID: UUID?
    var categoryID: UUID?

    /// Signed monthly equivalent (positive for income, negative for expense,
    /// zero for transfers). Used in fixed-cost / recurring-income analytics.
    var monthlyEquivalent: Double {
        let factor = frequency.monthlyFactor
        switch kind {
        case .income:   return  amount * factor
        case .expense:  return -amount * factor
        case .transfer: return 0
        }
    }
}
