import SwiftUI

/// Modal sheet to create or edit a recurrence (salary, rent, subscription,
/// automated investment, etc.). Captures cadence, start / end dates, the
/// affected account(s), and whether the engine should auto-apply each
/// occurrence at launch.
struct RecurrenceEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let recurrence: RecurringTransaction?

    @State private var name: String = ""
    @State private var kind: TransactionKind = .income
    @State private var amount: Double = 0
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var startDate: Date = .now
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var accountID: UUID?
    @State private var transferTargetID: UUID?
    @State private var categoryID: UUID?
    @State private var autoApply: Bool = true
    @State private var isActive: Bool = true
    @State private var note: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(recurrence == nil ? "Nouvelle récurrence" : "Modifier la récurrence")
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
                    TextField("Nom (ex : Salaire, Netflix)", text: $name)
                    HStack {
                        Text("Montant")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(Money.currencySymbol).foregroundStyle(.secondary)
                    }
                    Picker("Fréquence", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                }

                Section {
                    DatePicker("Première occurrence", selection: $startDate, displayedComponents: .date)
                    Toggle("Date de fin", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                    }
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
                            ForEach(store.categories.filter { $0.type == kind && !$0.isArchived }) { c in
                                Label(c.name, systemImage: c.systemImage).tag(UUID?.some(c.id))
                            }
                        }
                    }
                }

                Section {
                    Toggle("Active", isOn: $isActive)
                    Toggle("Appliquer automatiquement à l'échéance", isOn: $autoApply)
                }

                Section("Note") {
                    TextField("Optionnel", text: $note, axis: .vertical).lineLimit(2...3)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let recurrence {
                    Button("Supprimer", role: .destructive) {
                        store.deleteRecurrence(recurrence.id)
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
        .frame(width: 540, height: 700)
        .onAppear(perform: load)
    }

    private var isValid: Bool {
        guard !name.isEmpty, amount > 0, accountID != nil else { return false }
        if kind == .transfer { return transferTargetID != nil && transferTargetID != accountID }
        return true
    }

    private func tint(for k: TransactionKind) -> Color {
        switch k {
        case .income:   return Theme.positive
        case .expense:  return Theme.negative
        case .transfer: return Theme.accent
        }
    }

    private func load() {
        if let r = recurrence {
            name = r.name
            kind = r.kind
            amount = r.amount
            frequency = r.frequency
            startDate = r.startDate
            hasEndDate = r.endDate != nil
            endDate = r.endDate ?? endDate
            accountID = r.accountID
            transferTargetID = r.transferTargetID
            categoryID = r.categoryID
            autoApply = r.autoApply
            isActive = r.isActive
            note = r.note
        } else {
            accountID = store.activeAccounts.first { $0.kind.isTransactional }?.id
        }
    }

    private func save() {
        var r: RecurringTransaction
        if let existing = recurrence {
            r = existing
            r.name = name
            r.kind = kind
            r.amount = amount
            r.frequency = frequency
            r.startDate = startDate
            r.endDate = hasEndDate ? endDate : nil
            r.accountID = accountID
            r.transferTargetID = kind == .transfer ? transferTargetID : nil
            r.categoryID = kind == .transfer ? nil : categoryID
            r.autoApply = autoApply
            r.isActive = isActive
            r.note = note
            if r.nextDate < startDate { r.nextDate = startDate }
        } else {
            r = RecurringTransaction(
                name: name,
                amount: amount,
                kind: kind,
                frequency: frequency,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                nextDate: startDate,
                isActive: isActive,
                autoApply: autoApply,
                note: note,
                accountID: accountID,
                transferTargetID: kind == .transfer ? transferTargetID : nil,
                categoryID: kind == .transfer ? nil : categoryID
            )
        }
        store.upsert(r)
        dismiss()
    }
}
