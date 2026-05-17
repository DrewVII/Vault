import Foundation

/// Pure, side-effect-free financial computations over the `Store`.
///
/// Every function here is read-only: the engine never mutates state, never
/// touches disk, never performs IO. This makes it trivially testable and
/// reusable from any view that needs a number.
///
/// References used throughout:
/// - **Savings rate** = (income − expense) / income, target ≥ 20 %.
/// - **Runway** = liquid assets / average monthly burn, target ≥ 6 months.
/// - **50 / 30 / 20 rule** (Senator E. Warren): 50 % needs, 30 % wants, 20 % savings.
struct AnalyticsEngine {

    // MARK: - Net worth

    /// Total net worth = Σ (account contributions, signed for liabilities).
    @MainActor
    static func netWorth(_ store: Store) -> Double {
        store.activeAccounts.reduce(0) { $0 + store.netWorthContribution($1) }
    }

    /// Σ balances of all non-liability accounts marked "include in net worth".
    @MainActor
    static func assets(_ store: Store) -> Double {
        store.activeAccounts
            .filter { $0.includeInNetWorth && !$0.kind.isLiability }
            .reduce(0) { $0 + store.currentBalance($1) }
    }

    /// Σ |balances| of liability accounts (credit / debt). Always returned as
    /// a positive number — callers add the sign when needed.
    @MainActor
    static func liabilities(_ store: Store) -> Double {
        store.activeAccounts
            .filter { $0.includeInNetWorth && $0.kind.isLiability }
            .reduce(0) { $0 + abs(store.currentBalance($1)) }
    }

    /// Σ balances of "liquid" accounts (checking, savings, cash). Used as the
    /// numerator of the runway computation.
    @MainActor
    static func liquidAssets(_ store: Store) -> Double {
        store.activeAccounts
            .filter { $0.includeInNetWorth && $0.kind.assetClass == .liquid }
            .reduce(0) { $0 + store.currentBalance($1) }
    }

    /// Net-worth allocation grouped by `AssetClass` — used to drive the
    /// donut chart on the dashboard. Liabilities are returned separately as
    /// a positive amount with class `.liability` so the caller can decide
    /// whether to display them.
    @MainActor
    static func allocation(_ store: Store) -> [(AssetClass, Double)] {
        var bag: [AssetClass: Double] = [:]
        for a in store.activeAccounts where a.includeInNetWorth {
            bag[a.kind.assetClass, default: 0] += abs(store.currentBalance(a))
        }
        // Preserve the canonical class order so legend rows and chart slices
        // line up consistently.
        return AssetClass.allCases.compactMap { cls in
            guard let v = bag[cls], v > 0 else { return nil }
            return (cls, v)
        }
    }

    // MARK: - Cash-flow

    /// Sum of income / expense within the half-open window `[start, end)`.
    /// Transfers between user-owned accounts are intentionally ignored — they
    /// are neutral for cash-flow purposes.
    static func cashFlow(_ transactions: [Transaction], from start: Date, to end: Date)
        -> (income: Double, expense: Double)
    {
        var income = 0.0
        var expense = 0.0
        for t in transactions where t.date >= start && t.date < end {
            switch t.kind {
            case .income:   income  += t.amount
            case .expense:  expense += t.amount
            case .transfer: continue
            }
        }
        return (income, expense)
    }

    /// Convenience: cash-flow of the current calendar month.
    static func currentMonthCashFlow(_ transactions: [Transaction]) -> (income: Double, expense: Double) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? now
        return cashFlow(transactions, from: start, to: end)
    }

    /// Monthly cash-flow buckets for the **last N calendar months**, oldest
    /// first. Drives the 6-month bar chart on the dashboard.
    static func monthlyCashFlow(_ transactions: [Transaction], months: Int)
        -> [(date: Date, income: Double, expense: Double)]
    {
        let cal = Calendar.current
        let now = Date()
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        var result: [(Date, Double, Double)] = []
        for offset in stride(from: months - 1, through: 0, by: -1) {
            guard let start = cal.date(byAdding: .month, value: -offset, to: thisMonth),
                  let end   = cal.date(byAdding: .month, value: 1, to: start) else { continue }
            let cf = cashFlow(transactions, from: start, to: end)
            result.append((start, cf.income, cf.expense))
        }
        return result
    }

    // MARK: - Ratios

    /// `(income − expense) / income`, clamped to `[-1, 1]`. Returns `nil`
    /// when there is no income to divide by, which the UI surfaces as `—`.
    static func savingsRate(income: Double, expense: Double) -> Double? {
        guard income > 0 else { return nil }
        return max(min((income - expense) / income, 1), -1)
    }

    /// Expected fixed expenses per month, derived from the active recurring
    /// expense rules. The `monthlyEquivalent` factor handles non-monthly
    /// cadences (weekly → ×52/12, etc.).
    static func monthlyFixedExpenses(_ recurrences: [RecurringTransaction]) -> Double {
        recurrences
            .filter { $0.isActive && $0.kind == .expense }
            .reduce(0.0) { $0 + abs($1.monthlyEquivalent) }
    }

    static func monthlyRecurringIncome(_ recurrences: [RecurringTransaction]) -> Double {
        recurrences
            .filter { $0.isActive && $0.kind == .income }
            .reduce(0.0) { $0 + $1.monthlyEquivalent }
    }

    /// **Runway** — how many months the user could live on current liquid
    /// assets if all income stopped tomorrow.
    ///
    /// Burn rate is the **3-month trailing average of expenses**, with the
    /// declared fixed expenses used as a fall-back when there is no history.
    /// Returns `nil` if neither is available.
    @MainActor
    static func runwayMonths(_ store: Store) -> Double? {
        let liquid = liquidAssets(store)
        guard liquid > 0 else { return 0 }

        let last3 = monthlyCashFlow(store.transactions, months: 3)
        let avgExpense = last3.isEmpty
            ? 0
            : last3.map(\.expense).reduce(0, +) / Double(last3.count)
        let burn = avgExpense > 0 ? avgExpense : monthlyFixedExpenses(store.recurrences)
        guard burn > 0 else { return nil }
        return liquid / burn
    }

    /// Top expense categories of the current month, descending by amount.
    /// A `nil` category means the transaction was uncategorised.
    static func currentMonthByCategory(_ transactions: [Transaction], categories: [Category])
        -> [(category: Category?, total: Double)]
    {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? now

        var bag: [UUID?: Double] = [:]
        for t in transactions where t.kind == .expense && t.date >= start && t.date < end {
            bag[t.categoryID, default: 0] += t.amount
        }
        let catByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return bag.map { (key, total) in
            (key.flatMap { catByID[$0] }, total)
        }.sorted { $0.1 > $1.1 }
    }
}
