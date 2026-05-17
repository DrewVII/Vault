import SwiftUI

/// Searchable, filterable list of transactions grouped by day.
///
/// Filters compose: type (income / expense / transfer), account, and a free
/// text search across note, category name and account name.
struct TransactionsView: View {
    @EnvironmentObject private var store: Store

    @State private var search: String = ""
    @State private var filterKind: TransactionKind? = nil
    @State private var filterAccountID: UUID? = nil
    @State private var showAdd = false
    @State private var editing: Transaction? = nil

    var filtered: [Transaction] {
        store.transactions.filter { t in
            if let filterKind, t.kind != filterKind { return false }
            if let filterAccountID, t.accountID != filterAccountID && t.transferTargetID != filterAccountID { return false }
            if !search.isEmpty {
                let cat = store.category(t.categoryID)?.name ?? ""
                let acc = store.account(t.accountID)?.name ?? ""
                let hay = "\(t.note) \(cat) \(acc)"
                if !hay.localizedCaseInsensitiveContains(search) { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filtersBar
            Divider().background(Theme.stroke)
            if filtered.isEmpty {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: "Aucune transaction",
                    subtitle: "Saisis ta première dépense ou revenu avec ⌘N."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(grouped, id: \.0) { day, items in
                        Section {
                            ForEach(items) { t in
                                TransactionRow(transaction: t)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = t }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            store.deleteTransaction(t.id)
                                        } label: {
                                            Label("Supprimer", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            Text(DateFmt.short.string(from: day))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Label("Nouvelle", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddTransactionSheet() }
        .sheet(item: $editing) { tx in AddTransactionSheet(editing: tx) }
    }

    private var filtersBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 280)

            Picker("Type", selection: $filterKind) {
                Text("Tous types").tag(TransactionKind?.none)
                ForEach(TransactionKind.allCases) { k in
                    Text(k.label).tag(TransactionKind?.some(k))
                }
            }
            .frame(width: 140)

            Picker("Compte", selection: $filterAccountID) {
                Text("Tous comptes").tag(UUID?.none)
                ForEach(store.activeAccounts) { a in
                    Text(a.name).tag(UUID?.some(a.id))
                }
            }
            .frame(width: 180)

            Spacer()
            Text("\(filtered.count) résultat\(filtered.count > 1 ? "s" : "")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var grouped: [(Date, [Transaction])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }
}

struct TransactionRow: View {
    @EnvironmentObject private var store: Store
    let transaction: Transaction

    var body: some View {
        let category = store.category(transaction.categoryID)
        let account = store.account(transaction.accountID)
        let target = store.account(transaction.transferTargetID)

        HStack(spacing: 12) {
            ZStack {
                Circle().fill((category?.color ?? Theme.muted).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon(category: category))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(category?.color ?? Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(category: category)).font(.system(size: 13, weight: .medium))
                Text(subtitle(account: account, target: target, category: category))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(amountColor)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func icon(category: Category?) -> String {
        switch transaction.kind {
        case .income:   return category?.systemImage ?? "arrow.down.circle"
        case .expense:  return category?.systemImage ?? "arrow.up.circle"
        case .transfer: return "arrow.left.arrow.right"
        }
    }

    private func displayTitle(category: Category?) -> String {
        if !transaction.note.isEmpty { return transaction.note }
        if let c = category { return c.name }
        switch transaction.kind {
        case .income:   return "Revenu"
        case .expense:  return "Dépense"
        case .transfer: return "Virement"
        }
    }

    private func subtitle(account: Account?, target: Account?, category: Category?) -> String {
        switch transaction.kind {
        case .transfer:
            return "\(account?.name ?? "?") → \(target?.name ?? "?")"
        default:
            return "\(account?.name ?? "—") · \(category?.name ?? "Sans catégorie")"
        }
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .income:   return Theme.positive
        case .expense:  return Theme.negative
        case .transfer: return .secondary
        }
    }

    private var amountText: String {
        let raw = Money.format(transaction.amount)
        switch transaction.kind {
        case .income:   return "+ " + raw
        case .expense:  return "− " + raw
        case .transfer: return raw
        }
    }
}
