import SwiftUI

/// Budgets screen with two sections:
/// 1. **50 / 30 / 20 rule overview** — current allocation vs. target,
///    computed from the categorisation of this month's transactions.
/// 2. **Per-category budgets** — user-defined monthly ceilings with
///    spent / limit progress bars (green / amber / red).
struct BudgetView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Budget?
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ruleCard

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Budgets par catégorie",
                                     trailing: AnyView(
                                        Button {
                                            showAdd = true
                                        } label: {
                                            Label("Ajouter", systemImage: "plus")
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.borderless)
                                     ))
                        if store.budgets.isEmpty {
                            Text("Définis un plafond mensuel sur les catégories que tu veux suivre (ex : Restaurants, Loisirs).")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(store.budgets) { b in
                                BudgetRow(budget: b)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = b }
                                if b.id != store.budgets.last?.id {
                                    Divider().background(Theme.stroke)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .navigationTitle("Budgets")
        .sheet(isPresented: $showAdd) { BudgetEditor(budget: nil) }
        .sheet(item: $editing) { b in BudgetEditor(budget: b) }
    }

    private var ruleCard: some View {
        let income = max(AnalyticsEngine.monthlyRecurringIncome(store.recurrences),
                         AnalyticsEngine.currentMonthCashFlow(store.transactions).income)
        let cf = AnalyticsEngine.currentMonthCashFlow(store.transactions)
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? now

        var fixed = 0.0, variable = 0.0, discretionary = 0.0, savings = 0.0
        for t in store.transactions where t.date >= start && t.date < end {
            guard let cid = t.categoryID, let c = store.category(cid) else { continue }
            switch c.group {
            case .fixed:         if t.kind == .expense { fixed += t.amount }
            case .variable:      if t.kind == .expense { variable += t.amount }
            case .discretionary: if t.kind == .expense { discretionary += t.amount }
            case .savings:       if t.kind == .expense { savings += t.amount }
            default: break
            }
        }
        let needs = fixed + variable
        let wants = discretionary
        let saved = savings + max(cf.income - cf.expense, 0)

        return Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Règle 50 / 30 / 20")
                HStack(spacing: 14) {
                    ruleBlock(label: "Besoins", target: 0.5, actual: needs, base: income, tint: Theme.accent)
                    ruleBlock(label: "Envies",  target: 0.3, actual: wants, base: income, tint: Theme.warning)
                    ruleBlock(label: "Épargne", target: 0.2, actual: saved, base: income, tint: Theme.positive)
                }
                Text("Référence pédagogique. Adapte selon ta situation, ton horizon et tes objectifs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ruleBlock(label: String, target: Double, actual: Double, base: Double, tint: Color) -> some View {
        let ratio = base > 0 ? actual / base : 0
        let progress = min(ratio / target, 1.5)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text("Cible \(Pct.format(target, fractionDigits: 0))").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(Pct.format(ratio, fractionDigits: 0))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            ProgressView(value: max(min(progress, 1), 0))
                .progressViewStyle(.linear)
                .tint(tint)
            Text(Money.compact(actual) + " / " + Money.compact(base * target))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BudgetRow: View {
    @EnvironmentObject private var store: Store
    let budget: Budget

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? now
        let category = store.category(budget.categoryID)
        let spent = store.transactions
            .filter { $0.kind == .expense && $0.categoryID == budget.categoryID && $0.date >= start && $0.date < end }
            .reduce(0.0) { $0 + $1.amount }
        let ratio = budget.monthlyLimit > 0 ? spent / budget.monthlyLimit : 0
        let tint: Color = ratio < 0.7 ? Theme.positive : (ratio < 1 ? Theme.warning : Theme.negative)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category?.systemImage ?? "questionmark.circle")
                    .foregroundStyle(category?.color ?? .secondary)
                Text(category?.name ?? "Sans catégorie")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Money.format(spent)) / \(Money.format(budget.monthlyLimit))")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            ProgressView(value: min(ratio, 1))
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }
}

struct BudgetEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let budget: Budget?

    @State private var categoryID: UUID?
    @State private var monthlyLimit: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(budget == nil ? "Nouveau budget" : "Modifier le budget")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)

            Form {
                Picker("Catégorie", selection: $categoryID) {
                    Text("—").tag(UUID?.none)
                    ForEach(store.categories.filter { $0.type == .expense && !$0.isArchived }) { c in
                        Label(c.name, systemImage: c.systemImage).tag(UUID?.some(c.id))
                    }
                }
                HStack {
                    Text("Plafond mensuel")
                    Spacer()
                    TextField("0", value: $monthlyLimit, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                    Text(Money.currencySymbol).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let budget {
                    Button("Supprimer", role: .destructive) {
                        store.deleteBudget(budget.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Enregistrer") {
                    if let existing = budget {
                        var b = existing
                        b.categoryID = categoryID
                        b.monthlyLimit = monthlyLimit
                        store.upsert(b)
                    } else {
                        store.upsert(Budget(monthlyLimit: monthlyLimit, categoryID: categoryID))
                    }
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(categoryID == nil || monthlyLimit <= 0)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 460, height: 320)
        .onAppear {
            if let b = budget {
                categoryID = b.categoryID
                monthlyLimit = b.monthlyLimit
            }
        }
    }
}
