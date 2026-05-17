import SwiftUI

/// Identifies a top-level destination in the sidebar.
/// Used both as the `NavigationSplitView` selection value and to derive the
/// row label & SF Symbols icon.
enum SidebarTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, accounts, transactions, recurring, forecast, budgets, assistant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Tableau de bord"
        case .accounts:     return "Comptes"
        case .transactions: return "Transactions"
        case .recurring:    return "Récurrences"
        case .forecast:     return "Prévisions"
        case .budgets:      return "Budgets"
        case .assistant:    return "Assistant"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:    return "square.grid.2x2"
        case .accounts:     return "creditcard"
        case .transactions: return "list.bullet.rectangle"
        case .recurring:    return "repeat"
        case .forecast:     return "chart.line.uptrend.xyaxis"
        case .budgets:      return "target"
        case .assistant:    return "sparkles"
        }
    }
}

/// Root container: macOS-native `NavigationSplitView` with the sidebar on the
/// left and the selected detail screen on the right. A global ⌘N shortcut is
/// wired here so "new transaction" works from any screen.
struct RootView: View {
    @State private var selection: SidebarTab? = .dashboard
    @State private var showAddTransaction = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddTransaction = true
                        } label: {
                            Label("Nouvelle transaction", systemImage: "plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionSheet()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent)
                        .frame(width: 26, height: 26)
                    Image(systemName: "lock.shield")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("Vault")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)

            List(selection: $selection) {
                Section {
                    ForEach(SidebarTab.allCases) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.label, systemImage: tab.systemImage)
                                .font(.system(size: 13))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard:    DashboardView()
        case .accounts:     AccountsView()
        case .transactions: TransactionsView()
        case .recurring:    RecurringView()
        case .forecast:     ForecastView()
        case .budgets:      BudgetView()
        case .assistant:    AssistantView()
        }
    }
}
