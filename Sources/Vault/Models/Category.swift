import Foundation
import SwiftUI

/// High-level grouping used by the **50 / 30 / 20** budgeting rule.
///
/// - `.fixed` and `.variable` together count as **Needs** (50 %).
/// - `.discretionary` counts as **Wants** (30 %).
/// - `.savings` counts towards **Savings** (20 %).
/// - `.income` and `.other` are not part of the rule.
enum CategoryGroup: String, Codable, CaseIterable, Identifiable {
    case fixed
    case variable
    case discretionary
    case income
    case savings
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fixed:         return "Charges fixes"
        case .variable:      return "Charges variables"
        case .discretionary: return "Envies"
        case .income:        return "Revenus"
        case .savings:       return "Épargne"
        case .other:         return "Autre"
        }
    }
}

/// A label for a transaction (e.g. "Restaurants", "Salary").
///
/// `type` constrains the kind of transactions that can use this category —
/// an income category cannot be assigned to an expense. The default category
/// set is seeded by `SeedData.bootstrapIfNeeded(_:)`.
struct Category: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String

    /// SF Symbols name used as the category icon.
    var systemImage: String

    var colorHex: String
    var group: CategoryGroup
    var type: TransactionKind
    var isArchived: Bool = false
    var sortIndex: Int = 0

    var color: Color { Color(hex: colorHex) }
}
