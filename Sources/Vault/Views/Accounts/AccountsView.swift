import SwiftUI

/// Grid view of all user accounts with a summary row (assets / liabilities /
/// net worth) on top. Tap a card to edit it; right-click for the archive
/// shortcut.
struct AccountsView: View {
    @EnvironmentObject private var store: Store
    @State private var showAddAccount = false
    @State private var selected: Account?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryRow

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 14)], spacing: 14) {
                    ForEach(store.activeAccounts) { account in
                        AccountCard(account: account)
                            .contextMenu {
                                Button("Modifier") { selected = account }
                                Button("Archiver", role: .destructive) {
                                    var a = account
                                    a.isArchived = true
                                    store.upsert(a)
                                }
                            }
                            .onTapGesture { selected = account }
                    }
                    AddAccountTile { showAddAccount = true }
                }
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .navigationTitle("Comptes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddAccount = true } label: {
                    Label("Nouveau compte", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddAccount) { AccountEditor(account: nil) }
        .sheet(item: $selected) { acc in AccountEditor(account: acc) }
    }

    private var summaryRow: some View {
        let assets = AnalyticsEngine.assets(store)
        let liab   = AnalyticsEngine.liabilities(store)
        let net    = assets - liab
        return HStack(spacing: 14) {
            Card { StatLabel(label: "Actifs",          value: Money.format(assets), tint: Theme.positive) }
            Card { StatLabel(label: "Passifs",         value: Money.format(liab),   tint: Theme.negative) }
            Card { StatLabel(label: "Patrimoine net",  value: Money.format(net)) }
        }
    }
}

struct AccountCard: View {
    @EnvironmentObject private var store: Store
    let account: Account

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(account.color.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: account.kind.systemImage)
                            .foregroundStyle(account.color)
                            .font(.system(size: 16, weight: .medium))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).font(.system(size: 14, weight: .semibold))
                        Text(account.kind.label).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if account.kind.isLiability {
                        Pill(text: "Passif", tint: Theme.negative)
                    } else if !account.includeInNetWorth {
                        Pill(text: "Hors patrimoine", tint: .secondary)
                    }
                }

                let balance = store.currentBalance(account)
                Text(Money.format(balance))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(account.kind.isLiability ? Theme.negative : .primary)
                    .monospacedDigit()

                let count = store.transactions(for: account.id).count
                Text(account.kind.isTransactional
                     ? "\(count) transaction\(count > 1 ? "s" : "")"
                     : "Valorisation au \(DateFmt.short.string(from: account.manualValuationDate))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AddAccountTile: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("Nouveau compte")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}
