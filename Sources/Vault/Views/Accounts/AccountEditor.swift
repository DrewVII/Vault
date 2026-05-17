import SwiftUI

/// Modal sheet to create or edit an account. The same form handles every
/// account kind — the input fields adapt to whether the kind is transactional
/// (asks for an initial balance) or valuation-based (asks for a manual valuation).
struct AccountEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let account: Account?

    @State private var draft: Account = Account(name: "", kind: .checking)

    var isEditing: Bool { account != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Modifier le compte" : "Nouveau compte")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)

            Form {
                Section {
                    TextField("Nom", text: $draft.name)

                    Picker("Type", selection: $draft.kind) {
                        ForEach(AccountKind.allCases) { k in
                            Label(k.label, systemImage: k.systemImage).tag(k)
                        }
                    }

                    if draft.kind.isTransactional {
                        HStack {
                            Text("Solde initial")
                            Spacer()
                            TextField("0", value: $draft.initialBalance, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                            Text(Money.currencySymbol).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Valorisation actuelle")
                            Spacer()
                            TextField("0", value: $draft.manualValuation, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                            Text(Money.currencySymbol).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Couleur") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 28))], spacing: 10) {
                        ForEach(Theme.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().stroke(Color.primary, lineWidth: hex == draft.colorHex ? 2 : 0)
                                )
                                .onTapGesture { draft.colorHex = hex }
                        }
                    }
                }

                Section {
                    Toggle("Inclure dans le patrimoine net", isOn: $draft.includeInNetWorth)
                }
            }
            .formStyle(.grouped)

            HStack {
                if isEditing {
                    Button("Supprimer", role: .destructive) {
                        if let account { store.deleteAccount(account.id) }
                        dismiss()
                    }
                }
                Spacer()
                Button("Enregistrer", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 500, height: 560)
        .onAppear {
            if let a = account {
                draft = a
            } else {
                draft = Account(name: "", kind: .checking, colorHex: Theme.palette[0])
            }
        }
    }

    private func save() {
        if !draft.kind.isTransactional {
            draft.manualValuationDate = .now
        }
        store.upsert(draft)
        dismiss()
    }
}
