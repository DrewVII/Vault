import Foundation

/// A monthly spending ceiling for a single category.
///
/// The Budgets screen compares the sum of current-month expenses in
/// `categoryID` against `monthlyLimit` and colours the progress bar:
/// green ≤ 70 %, amber ≤ 100 %, red > 100 %.
struct Budget: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var monthlyLimit: Double
    var categoryID: UUID?
    var createdAt: Date = .now
}
