import Foundation
import SwiftUI

/// The complete persisted state of the application — a single Codable graph
/// stored as JSON on disk. Keeping everything in one file makes export, backup
/// and debugging trivial.
struct StoreState: Codable {
    /// Bumped manually whenever the schema requires a migration.
    var schemaVersion: Int = 1

    var accounts: [Account] = []
    var transactions: [Transaction] = []
    var recurrences: [RecurringTransaction] = []
    var categories: [Category] = []
    var budgets: [Budget] = []
}

/// Single source of truth for the app's data.
///
/// Design choices:
/// - **Plain `Codable` JSON** instead of Core Data / SwiftData. The toolchain
///   needs no Xcode-only macros, and the on-disk format is human-readable.
/// - **Reference relationships expressed by `UUID`**, not by object pointers,
///   so the value-typed models survive any number of clones / encodings.
/// - **`@MainActor`** because the store is also the `ObservableObject` that
///   drives SwiftUI views — keeping mutations on the main actor avoids the
///   "publishing changes from a background thread" footgun.
@MainActor
final class Store: ObservableObject {

    /// Observable state. Views read this through computed accessors below;
    /// mutations go through the `upsert` / `delete` / `mutate` helpers so we
    /// can centralise persistence.
    @Published private(set) var state: StoreState

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Used to coalesce successive `save()` calls happening in the same
    /// run-loop turn into a single disk write.
    private var saveScheduled = false

    // MARK: - Init

    /// Loads `~/Library/Application Support/Vault/store.json` if it exists,
    /// otherwise starts from a blank `StoreState`.
    init() {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.homeDirectoryForCurrentUser
        let dir = appSupport.appendingPathComponent("Vault", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("store.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? decoder.decode(StoreState.self, from: data) {
            self.state = loaded
        } else {
            self.state = StoreState()
        }
    }

    // MARK: - Persistence

    /// Persists the current state to disk.
    ///
    /// Calls are coalesced: ten successive `save()` invocations in the same
    /// run-loop turn produce a single atomic write. This keeps the UI responsive
    /// during bulk mutations (e.g. importing a list of transactions).
    func save() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            do {
                let data = try self.encoder.encode(self.state)
                try data.write(to: self.fileURL, options: .atomic)
            } catch {
                NSLog("Vault: failed to save store: \(error)")
            }
        }
    }

    // MARK: - Lookups

    /// All accounts, sorted by user-defined order.
    var accounts: [Account] { state.accounts.sorted { $0.sortIndex < $1.sortIndex } }

    /// Active accounts (not archived).
    var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    /// All transactions, most recent first.
    var transactions: [Transaction] { state.transactions.sorted { $0.date > $1.date } }

    /// All recurrences, soonest due first.
    var recurrences: [RecurringTransaction] { state.recurrences.sorted { $0.nextDate < $1.nextDate } }

    var categories: [Category] { state.categories.sorted { $0.sortIndex < $1.sortIndex } }
    var budgets: [Budget] { state.budgets }

    func account(_ id: UUID?) -> Account? {
        guard let id else { return nil }
        return state.accounts.first { $0.id == id }
    }

    func category(_ id: UUID?) -> Category? {
        guard let id else { return nil }
        return state.categories.first { $0.id == id }
    }

    /// Every transaction that involves the given account, either as source
    /// account or as the target of a transfer.
    func transactions(for accountID: UUID) -> [Transaction] {
        state.transactions.filter { $0.accountID == accountID || $0.transferTargetID == accountID }
    }

    // MARK: - Computed balances

    /// The current balance of an account.
    ///
    /// - For **transactional** accounts (checking, savings, cash, credit) the
    ///   balance is derived from `initialBalance + Σ signed transactions`.
    /// - For **valuation** accounts (investment, real estate, other) the
    ///   balance is the manual valuation last entered by the user.
    func currentBalance(_ account: Account) -> Double {
        if account.kind.isTransactional {
            let total = state.transactions.reduce(0.0) { $0 + $1.signedAmount(for: account.id) }
            return account.initialBalance + total
        } else {
            return account.manualValuation
        }
    }

    /// Net-worth contribution of an account (negative for liabilities).
    /// Returns `0` if the account is archived or excluded from net worth.
    func netWorthContribution(_ account: Account) -> Double {
        guard account.includeInNetWorth, !account.isArchived else { return 0 }
        let v = currentBalance(account)
        return account.kind.isLiability ? -abs(v) : v
    }

    // MARK: - Mutations

    /// Inserts or updates an account by its identity.
    func upsert(_ account: Account) {
        if let i = state.accounts.firstIndex(where: { $0.id == account.id }) {
            state.accounts[i] = account
        } else {
            var a = account
            a.sortIndex = state.accounts.count
            state.accounts.append(a)
        }
        save()
    }

    /// Removes an account and every transaction / recurrence that referenced
    /// it (we cannot leave orphan IDs pointing into a void).
    func deleteAccount(_ id: UUID) {
        state.accounts.removeAll { $0.id == id }
        state.transactions.removeAll { $0.accountID == id || $0.transferTargetID == id }
        state.recurrences.removeAll { $0.accountID == id || $0.transferTargetID == id }
        save()
    }

    func upsert(_ tx: Transaction) {
        if let i = state.transactions.firstIndex(where: { $0.id == tx.id }) {
            state.transactions[i] = tx
        } else {
            state.transactions.append(tx)
        }
        save()
    }

    func deleteTransaction(_ id: UUID) {
        state.transactions.removeAll { $0.id == id }
        save()
    }

    func upsert(_ r: RecurringTransaction) {
        if let i = state.recurrences.firstIndex(where: { $0.id == r.id }) {
            state.recurrences[i] = r
        } else {
            state.recurrences.append(r)
        }
        save()
    }

    /// Deletes a recurrence definition. Generated transactions are preserved
    /// (they represent real history, not the rule that produced them).
    func deleteRecurrence(_ id: UUID) {
        state.recurrences.removeAll { $0.id == id }
        save()
    }

    func upsert(_ c: Category) {
        if let i = state.categories.firstIndex(where: { $0.id == c.id }) {
            state.categories[i] = c
        } else {
            state.categories.append(c)
        }
        save()
    }

    func upsert(_ b: Budget) {
        if let i = state.budgets.firstIndex(where: { $0.id == b.id }) {
            state.budgets[i] = b
        } else {
            state.budgets.append(b)
        }
        save()
    }

    func deleteBudget(_ id: UUID) {
        state.budgets.removeAll { $0.id == id }
        save()
    }

    /// Apply a free-form mutation to the underlying state, then schedule a save.
    /// Useful for batch operations (seeding, migrations, transactional changes).
    func mutate(_ block: (inout StoreState) -> Void) {
        block(&state)
        save()
    }
}
