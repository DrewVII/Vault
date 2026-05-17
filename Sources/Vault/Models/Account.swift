import Foundation
import SwiftUI

/// Semantic classification of an account.
///
/// `isTransactional` distinguishes accounts whose balance is **derived** from
/// the transaction log (checking, savings, cash, credit) from "valuation"
/// accounts (investment, real estate, other) whose balance is entered by hand
/// because there are no per-line movements to track.
///
/// `isLiability` flags accounts whose balance subtracts from net worth.
enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case checking
    case savings
    case cash
    case investment
    case realEstate
    case credit
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .checking:   return "Courant"
        case .savings:    return "Épargne"
        case .cash:       return "Espèces"
        case .investment: return "Investissement"
        case .realEstate: return "Immobilier"
        case .credit:     return "Crédit"
        case .other:      return "Autre"
        }
    }

    var systemImage: String {
        switch self {
        case .checking:   return "creditcard"
        case .savings:    return "banknote"
        case .cash:       return "eurosign.circle"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .realEstate: return "house"
        case .credit:     return "minus.circle"
        case .other:      return "square.stack"
        }
    }

    var isTransactional: Bool {
        switch self {
        case .checking, .savings, .cash, .credit: return true
        case .investment, .realEstate, .other:    return false
        }
    }

    var isLiability: Bool { self == .credit }

    var assetClass: AssetClass {
        switch self {
        case .checking, .cash, .savings: return .liquid
        case .investment:                return .invested
        case .realEstate:                return .property
        case .credit:                    return .liability
        case .other:                     return .other
        }
    }
}

enum AssetClass: String, Codable, CaseIterable, Identifiable {
    case liquid, invested, property, other, liability
    var id: String { rawValue }
    var label: String {
        switch self {
        case .liquid:    return "Liquidités"
        case .invested:  return "Investissements"
        case .property:  return "Immobilier"
        case .other:     return "Autre"
        case .liability: return "Passifs"
        }
    }
    var color: Color {
        switch self {
        case .liquid:    return Theme.accent
        case .invested:  return Theme.positive
        case .property:  return .orange
        case .other:     return .purple
        case .liability: return Theme.negative
        }
    }
}

/// A bank account, cash envelope, brokerage account, real-estate asset or
/// liability. Pure value type — relationships to transactions and recurrences
/// are expressed by `UUID` references stored on those records, not here.
///
/// Use `Store.currentBalance(_:)` to read a current balance rather than the
/// stored fields, because the value depends on `kind` (transactional accounts
/// derive their balance from the log, valuation accounts use `manualValuation`).
struct Account: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: AccountKind

    /// Opening balance for transactional accounts. Ignored for valuation accounts.
    var initialBalance: Double = 0

    /// Hand-entered valuation for non-transactional accounts (investment, real estate, other).
    var manualValuation: Double = 0
    var manualValuationDate: Date = .now

    var colorHex: String = Theme.accentHex

    /// Whether this account participates in the net-worth aggregate.
    /// Set to `false` for accounts you want to track without polluting the headline.
    var includeInNetWorth: Bool = true

    var isArchived: Bool = false
    var createdAt: Date = .now
    var sortIndex: Int = 0

    var color: Color { Color(hex: colorHex) }
}
