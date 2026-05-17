import SwiftUI

/// Lists every recurrence rule with a summary row on top (monthly recurring
/// income, monthly fixed expenses, net recurring cash-flow). The list also
/// shows the monthly-equivalent burn for each row so the user can compare
/// cadences at a glance.
struct RecurringView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: RecurringTransaction?
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary

                if store.recurrences.isEmpty {
                    Card {
                        EmptyStateView(
                            systemImage: "repeat",
                            title: "Aucune récurrence",
                            subtitle: "Ajoute ton salaire, un loyer ou un investissement automatique pour activer les prévisions."
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Card {
                        VStack(spacing: 0) {
                            SectionTitle("Échéancier").padding(.bottom, 12)
                            ForEach(store.recurrences) { r in
                                RecurringRow(recurrence: r)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = r }
                                if r.id != store.recurrences.last?.id {
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
        .navigationTitle("Récurrences")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Label("Nouvelle récurrence", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) { RecurrenceEditor(recurrence: nil) }
        .sheet(item: $editing) { r in RecurrenceEditor(recurrence: r) }
    }

    private var summary: some View {
        let income  = AnalyticsEngine.monthlyRecurringIncome(store.recurrences)
        let expense = AnalyticsEngine.monthlyFixedExpenses(store.recurrences)
        let net = income - expense
        return HStack(spacing: 14) {
            Card { StatLabel(label: "Revenus mensuels récurrents", value: Money.format(income), tint: Theme.positive) }
            Card { StatLabel(label: "Charges fixes mensuelles",    value: Money.format(expense), tint: Theme.negative) }
            Card { StatLabel(label: "Cash-flow récurrent",         value: Money.format(net, signed: true),
                             tint: net >= 0 ? Theme.positive : Theme.negative) }
        }
    }
}

struct RecurringRow: View {
    @EnvironmentObject private var store: Store
    let recurrence: RecurringTransaction
    var body: some View {
        let category = store.category(recurrence.categoryID)
        let account = store.account(recurrence.accountID)

        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: icon(category: category)).foregroundStyle(tint).font(.system(size: 13))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(recurrence.name).font(.system(size: 13, weight: .medium))
                    Pill(text: recurrence.frequency.label, tint: .secondary)
                    if !recurrence.isActive {
                        Pill(text: "Pause", tint: .secondary)
                    }
                }
                Text("\(account?.name ?? "—") · prochaine \(DateFmt.short.string(from: recurrence.nextDate))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text("≈ \(Money.compact(abs(recurrence.monthlyEquivalent))) / mois")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func icon(category: Category?) -> String {
        switch recurrence.kind {
        case .income:   return category?.systemImage ?? "arrow.down.circle"
        case .expense:  return category?.systemImage ?? "arrow.up.circle"
        case .transfer: return "arrow.left.arrow.right"
        }
    }

    private var tint: Color {
        switch recurrence.kind {
        case .income:   return Theme.positive
        case .expense:  return Theme.negative
        case .transfer: return Theme.accent
        }
    }

    private var amount: String {
        let v = Money.format(recurrence.amount)
        switch recurrence.kind {
        case .income:   return "+ \(v)"
        case .expense:  return "− \(v)"
        case .transfer: return v
        }
    }
}
