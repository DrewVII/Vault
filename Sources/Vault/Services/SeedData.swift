import Foundation

/// First-launch seeding. Populates a brand-new store with a sensible default
/// category set and one Checking account so the dashboard isn't empty out of
/// the box.
///
/// Idempotent: calling `bootstrapIfNeeded` repeatedly only inserts data when
/// the corresponding collection is empty.
enum SeedData {

    /// Seeds default categories and a default Checking account if the store
    /// is empty. Safe to call on every launch.
    @MainActor
    static func bootstrapIfNeeded(_ store: Store) {
        var didChange = false

        if store.state.categories.isEmpty {
            let defs: [(String, String, String, CategoryGroup, TransactionKind)] = [
                ("Salaire",         "briefcase",                Theme.palette[1], .income, .income),
                ("Revenus passifs", "leaf",                     Theme.palette[1], .income, .income),
                ("Investissements", "chart.line.uptrend.xyaxis",Theme.palette[1], .income, .income),
                ("Autres revenus",  "plus.circle",              Theme.palette[1], .income, .income),
                ("Logement",        "house",                    Theme.palette[3], .fixed,  .expense),
                ("Abonnements",     "repeat",                   Theme.palette[3], .fixed,  .expense),
                ("Assurances",      "shield",                   Theme.palette[3], .fixed,  .expense),
                ("Crédit",          "creditcard",               Theme.palette[3], .fixed,  .expense),
                ("Énergie",         "bolt",                     Theme.palette[3], .fixed,  .expense),
                ("Courses",         "cart",                     Theme.palette[5], .variable, .expense),
                ("Transport",       "car",                      Theme.palette[5], .variable, .expense),
                ("Santé",           "cross.case",               Theme.palette[5], .variable, .expense),
                ("Restaurants",     "fork.knife",               Theme.palette[6], .discretionary, .expense),
                ("Loisirs",         "gamecontroller",           Theme.palette[6], .discretionary, .expense),
                ("Voyages",         "airplane",                 Theme.palette[6], .discretionary, .expense),
                ("Shopping",        "bag",                      Theme.palette[6], .discretionary, .expense),
                ("Épargne",         "banknote",                 Theme.palette[4], .savings, .expense),
            ]
            store.mutate { state in
                for (i, d) in defs.enumerated() {
                    state.categories.append(Category(
                        name: d.0,
                        systemImage: d.1,
                        colorHex: d.2,
                        group: d.3,
                        type: d.4,
                        sortIndex: i
                    ))
                }
            }
            didChange = true
        }

        if store.state.accounts.isEmpty {
            store.mutate { state in
                state.accounts.append(Account(
                    name: "Compte courant",
                    kind: .checking,
                    initialBalance: 0,
                    colorHex: Theme.palette[0],
                    sortIndex: 0
                ))
            }
            didChange = true
        }

        if didChange { store.save() }
    }
}
