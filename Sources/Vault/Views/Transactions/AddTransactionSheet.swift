import SwiftUI

/// Modal sheet to create or edit a transaction. A segmented switch on top
/// toggles between income, expense and transfer — the form fields adapt
/// (transfers ask for two accounts and no category, the rest ask for a
/// category filtered by transaction type).
struct AddTransactionSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let editing: Transaction?

    @State private var kind: TransactionKind = .expense
    @State private var amount: Double = 0
    @State private var date: Date = .now
    @State private var accountID: UUID?
    @State private var transferTargetID: UUID?
    @State private var categoryID: UUID?
    @State private var note: String = ""

    init(editing: Transaction? = nil) {
        self.editing = editing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "Nouvelle transaction" : "Modifier la transaction")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)

            HStack(spacing: 8) {
                ForEach(TransactionKind.allCases) { k in
                    Button {
                        kind = k
                        if k != .transfer { transferTargetID = nil }
                        if let cid = categoryID,
                           let cat = store.category(cid),
                           cat.type != k, k != .transfer {
                            categoryID = nil
                        }
                    } label: {
                        Text(k.label)
                            .font(.system(size: 13, weight: kind == k ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(kind == k ? tint(for: k).opacity(0.18) : Color.clear)
                            )
                            .foregroundStyle(kind == k ? tint(for: k) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Form {
                Section {
                    HStack {
                        Text("Montant")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text(Money.currencySymbol).foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }

                Section {
                    Picker(kind == .transfer ? "Compte source" : "Compte", selection: $accountID) {
                        Text("—").tag(UUID?.none)
                        ForEach(store.activeAccounts) { a in
                            Text(a.name).tag(UUID?.some(a.id))
                        }
                    }
                    if kind == .transfer {
                        Picker("Compte cible", selection: $transferTargetID) {
                            Text("—").tag(UUID?.none)
                            ForEach(store.activeAccounts.filter { $0.id != accountID }) { a in
                                Text(a.name).tag(UUID?.some(a.id))
                            }
                        }
                    } else {
                        Picker("Catégorie", selection: $categoryID) {
                            Text("Aucune").tag(UUID?.none)
                            ForEach(filteredCategories) { c in
                                Label(c.name, systemImage: c.systemImage).tag(UUID?.some(c.id))
                            }
                        }
                    }
                }

                Section("Note") {
                    TextField("Optionnel", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let editing {
                    Button("Supprimer", role: .destructive) {
                        store.deleteTransaction(editing.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Enregistrer", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 520, height: 580)
        .onAppear(perform: load)
    }

    private var isValid: Bool {
        guard amount > 0, accountID != nil else { return false }
        if kind == .transfer { return transferTargetID != nil && transferTargetID != accountID }
        return true
    }

    private var filteredCategories: [Category] {
        store.categories.filter { $0.type == kind && !$0.isArchived }
    }

    private func tint(for k: TransactionKind) -> Color {
        switch k {
        case .income:   return Theme.positive
        case .expense:  return Theme.negative
        case .transfer: return Theme.accent
        }
    }

    private func load() {
        if let t = editing {
            kind = t.kind
            amount = t.amount
            date = t.date
            accountID = t.accountID
            transferTargetID = t.transferTargetID
            categoryID = t.categoryID
            note = t.note
        } else {
            accountID = store.activeAccounts.first { $0.kind.isTransactional }?.id
        }
    }

    private func save() {
        var tx: Transaction
        if let e = editing {
            tx = e
            tx.kind = kind
            tx.amount = amount
            tx.date = date
            tx.accountID = accountID
            tx.transferTargetID = kind == .transfer ? transferTargetID : nil
            tx.categoryID = kind == .transfer ? nil : categoryID
            tx.note = note
        } else {
            tx = Transaction(
                date: date,
                amount: amount,
                kind: kind,
                note: note,
                accountID: accountID,
                categoryID: kind == .transfer ? nil : categoryID,
                transferTargetID: kind == .transfer ? transferTargetID : nil
            )
        }
        store.upsert(tx)
        dismiss()
    }
}
