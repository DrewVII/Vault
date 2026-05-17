import Foundation

/// Materialises due recurrences into real `Transaction`s.
///
/// Called once at app launch from `VaultApp.init()`. For every recurrence
/// whose `nextDate` is in the past:
/// 1. Generate a `Transaction` reflecting that occurrence.
/// 2. Tag it with `sourceRecurrenceID` so we can trace history back to the rule.
/// 3. Advance `nextDate` by the recurrence's cadence.
///
/// This is idempotent: if you open the app three times in a row, you won't get
/// triplicate paychecks — only the occurrences that haven't been produced yet
/// are inserted.
struct RecurrenceEngine {

    /// Applies every active recurrence whose `nextDate` is ≤ `now`.
    /// The function is `@MainActor` because it mutates the observable store
    /// that drives SwiftUI.
    @MainActor
    static func applyDue(_ store: Store, now: Date = .now) {
        store.mutate { state in
            for i in state.recurrences.indices {
                guard state.recurrences[i].isActive,
                      state.recurrences[i].autoApply else { continue }

                // Defence-in-depth cap to avoid an unbounded loop if a
                // misconfigured cadence ever returned the same date.
                var safety = 0
                while state.recurrences[i].nextDate <= now {
                    if let end = state.recurrences[i].endDate,
                       state.recurrences[i].nextDate > end { break }
                    safety += 1
                    if safety > 600 { break }

                    let r = state.recurrences[i]
                    let tx = Transaction(
                        date: r.nextDate,
                        amount: r.amount,
                        kind: r.kind,
                        note: r.name.isEmpty ? r.note : r.name,
                        accountID: r.accountID,
                        categoryID: r.kind == .transfer ? nil : r.categoryID,
                        transferTargetID: r.kind == .transfer ? r.transferTargetID : nil,
                        sourceRecurrenceID: r.id
                    )
                    state.transactions.append(tx)
                    state.recurrences[i].lastAppliedDate = state.recurrences[i].nextDate
                    state.recurrences[i].nextDate = r.frequency.nextDate(after: state.recurrences[i].nextDate)
                }
            }
        }
    }
}
