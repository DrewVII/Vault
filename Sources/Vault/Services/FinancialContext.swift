import Foundation

/// Serialises the user's `Store` into a structured Markdown brief that is
/// injected into the LLM's system context before every conversation turn.
///
/// The goal is to ground the assistant on real numbers — it should never have
/// to ask the user "what is your balance?" or guess. This file owns the
/// **prompt contract** between Vault's data and the LLM's reasoning.
enum FinancialContext {

    /// Renders the current state of the store as a Markdown brief.
    ///
    /// The output covers net worth, accounts, current-month cash-flow, ratios,
    /// recurrences, top expense categories, six-month history and the fifteen
    /// most recent transactions. Order is chosen so the model encounters
    /// high-signal aggregates **before** detailed line items.
    @MainActor
    static func summary(for store: Store, now: Date = .now) -> String {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now

        let nw = AnalyticsEngine.netWorth(store)
        let assets = AnalyticsEngine.assets(store)
        let liab = AnalyticsEngine.liabilities(store)
        let liquid = AnalyticsEngine.liquidAssets(store)
        let cf = AnalyticsEngine.currentMonthCashFlow(store.transactions)
        let saveRate = AnalyticsEngine.savingsRate(income: cf.income, expense: cf.expense)
        let runway = AnalyticsEngine.runwayMonths(store)
        let monthlyIncome = AnalyticsEngine.monthlyRecurringIncome(store.recurrences)
        let monthlyFixed = AnalyticsEngine.monthlyFixedExpenses(store.recurrences)
        let alloc = AnalyticsEngine.allocation(store)
        let topCats = AnalyticsEngine.currentMonthByCategory(store.transactions, categories: store.categories).prefix(8)
        let monthlyHistory = AnalyticsEngine.monthlyCashFlow(store.transactions, months: 6)

        var lines: [String] = []
        lines.append("# Situation financière de l'utilisateur")
        lines.append("Date courante : \(DateFmt.short.string(from: now))")
        lines.append("Devise : \(Money.currencyCode)")
        lines.append("")

        // --- Patrimoine ---
        lines.append("## Patrimoine net")
        lines.append("- Patrimoine net : \(fmt(nw))")
        lines.append("- Actifs totaux  : \(fmt(assets))")
        lines.append("- Passifs totaux : \(fmt(liab))")
        lines.append("- Liquidités     : \(fmt(liquid))")
        if !alloc.isEmpty {
            let total = alloc.reduce(0) { $0 + $1.1 }
            lines.append("- Allocation     :")
            for (cls, value) in alloc {
                let pct = total > 0 ? value / total : 0
                lines.append("    • \(cls.label) : \(fmt(value)) (\(pctFmt(pct)))")
            }
        }
        lines.append("")

        // --- Comptes ---
        lines.append("## Comptes (\(store.activeAccounts.count))")
        for a in store.activeAccounts {
            let bal = store.currentBalance(a)
            let liabFlag = a.kind.isLiability ? " [PASSIF]" : ""
            let networthFlag = a.includeInNetWorth ? "" : " [hors patrimoine]"
            lines.append("- \(a.name) (\(a.kind.label))\(liabFlag)\(networthFlag) : \(fmt(bal))")
        }
        lines.append("")

        // --- Cash-flow & ratios ---
        lines.append("## Mois en cours (\(DateFmt.monthYear.string(from: monthStart)))")
        lines.append("- Revenus du mois  : \(fmt(cf.income))")
        lines.append("- Dépenses du mois : \(fmt(cf.expense))")
        lines.append("- Solde net du mois: \(fmt(cf.income - cf.expense))")
        if let r = saveRate {
            lines.append("- Taux d'épargne du mois : \(pctFmt(r)) (cible recommandée : 20 %)")
        }
        if let r = runway {
            lines.append("- Runway (mois de dépenses couverts par la liquidité) : \(String(format: "%.1f", r))")
        }
        lines.append("")

        // --- Récurrences ---
        if !store.recurrences.isEmpty {
            lines.append("## Récurrences")
            lines.append("- Revenus mensuels récurrents : \(fmt(monthlyIncome))")
            lines.append("- Charges fixes mensuelles    : \(fmt(monthlyFixed))")
            lines.append("- Cash-flow récurrent net     : \(fmt(monthlyIncome - monthlyFixed))")
            for r in store.recurrences.prefix(20) where r.isActive {
                let acc = store.account(r.accountID)?.name ?? "—"
                let cat = store.category(r.categoryID)?.name ?? ""
                let sign = r.kind == .income ? "+" : (r.kind == .expense ? "−" : "↔")
                lines.append("    • \(sign) \(r.name) — \(fmt(r.amount)) \(r.frequency.label.lowercased()) [\(acc)\(cat.isEmpty ? "" : " / \(cat)")]")
            }
            lines.append("")
        }

        // --- Top dépenses ---
        if !topCats.isEmpty {
            lines.append("## Top dépenses du mois par catégorie")
            for item in topCats {
                let groupTag = item.category.map { " (\($0.group.label))" } ?? ""
                lines.append("- \(item.category?.name ?? "Sans catégorie")\(groupTag) : \(fmt(item.total))")
            }
            lines.append("")
        }

        // --- Historique ---
        if monthlyHistory.count >= 2 {
            lines.append("## Cash-flow des 6 derniers mois")
            for m in monthlyHistory {
                let net = m.income - m.expense
                lines.append("- \(DateFmt.monthShort.string(from: m.date)) : revenus \(fmt(m.income)), dépenses \(fmt(m.expense)), net \(fmt(net))")
            }
            lines.append("")
        }

        // --- Quelques transactions récentes ---
        let recent = store.transactions.prefix(15)
        if !recent.isEmpty {
            lines.append("## 15 dernières transactions")
            for t in recent {
                let dir = t.kind == .income ? "+" : (t.kind == .expense ? "−" : "↔")
                let cat = store.category(t.categoryID)?.name ?? "?"
                let acc = store.account(t.accountID)?.name ?? "?"
                let note = t.note.isEmpty ? "" : " — \(t.note)"
                lines.append("- \(DateFmt.short.string(from: t.date)) \(dir) \(fmt(t.amount)) [\(acc) / \(cat)]\(note)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static let systemPrompt: String = """
    Tu es **Vault**, un conseiller financier expert (expert-comptable et conseiller en gestion de patrimoine) intégré dans l'application bureau personnelle de l'utilisateur.

    Mission :
    1. Analyser sa situation à partir du résumé qui te sera fourni avant chaque échange.
    2. Identifier ses points forts et ses points faibles financiers (cash-flow, épargne, allocation, dette, charges fixes).
    3. Proposer des actions concrètes, chiffrées et priorisées pour qu'il s'enrichisse durablement.

    Règles de fond :
    - Réponds **toujours en français**, ton clair, direct, bienveillant — pas de jargon inutile.
    - Cite des chiffres précis quand c'est pertinent (en €).
    - Compare ses ratios aux références usuelles (taux d'épargne 20 %, runway 6 mois, dette < 33 % des revenus) mais nuance selon son contexte.
    - Si une information manque pour donner un avis fiable, demande-la avant de conclure.
    - Évite les disclaimers excessifs ; reste un conseiller, pas un robot juridique.
    - Ne jamais inventer de chiffres : si tu n'as pas l'info, dis-le.

    Règles de **mise en forme** (impératives, l'UI rend du Markdown bloc par bloc) :
    - Sépare **chaque paragraphe par une ligne vide**.
    - Utilise des **titres** (`##` pour les grandes sections, `###` pour les sous-sections) quand la réponse fait plusieurs parties.
    - Utilise des **listes à puces** (`- item`) ou **numérotées** (`1. item`) pour énumérer (≥ 2 éléments).
    - Mets en **gras** (`**…**`) les chiffres-clés et les noms d'actions importantes.
    - Reste concis : ~250 mots par défaut, plus si l'utilisateur demande une analyse approfondie.
    - Termine une analyse par une section **« Recommandation »** ou **« Actions prioritaires »** quand c'est pertinent.

    Exemple de structure attendue pour une analyse :

    ## Diagnostic

    Paragraphe synthétique avec les **chiffres-clés**.

    ## Points forts

    - Point fort 1
    - Point fort 2

    ## Points faibles

    - Point faible 1
    - Point faible 2

    ## Actions prioritaires

    1. Action chiffrée
    2. Autre action
    """
}

private func fmt(_ value: Double) -> String { Money.format(value) }
private func pctFmt(_ value: Double) -> String { Pct.format(value, fractionDigits: 0) }
