import SwiftUI

/// Settings window (⌘,). Lets the user pick a currency code, appearance
/// preference and reseed the default categories.
struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage("vault.currencyCode") private var currencyCode: String = "EUR"
    @AppStorage("vault.colorScheme")  private var colorScheme: String = "system"

    var body: some View {
        Form {
            Section("Devise") {
                Picker("Code", selection: $currencyCode) {
                    Text("Euro (€)").tag("EUR")
                    Text("Dollar US ($)").tag("USD")
                    Text("Livre sterling (£)").tag("GBP")
                    Text("Franc suisse (CHF)").tag("CHF")
                    Text("Yen (¥)").tag("JPY")
                }
            }

            Section("Apparence") {
                Picker("Thème", selection: $colorScheme) {
                    Text("Système").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }
            }

            Section("Données") {
                Button("Réappliquer les catégories par défaut") {
                    SeedData.bootstrapIfNeeded(store)
                }
                Text("Stockage : ~/Library/Application Support/Vault/store.json")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Vault — toutes tes données restent en local sur ce Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
