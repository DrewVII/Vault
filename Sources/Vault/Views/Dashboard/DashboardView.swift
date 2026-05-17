import SwiftUI
import Charts

/// Headline screen of the app: four KPI cards (net worth, cash-flow, savings
/// rate, runway), a 12-month forecast chart, an asset-allocation donut,
/// a 6-month cash-flow bar chart, the top expense categories of the month
/// and the next upcoming recurrences. All values are computed live from the
/// `Store` via `AnalyticsEngine` and `ForecastEngine`.
struct DashboardView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    netWorthCard
                    cashFlowCard
                    savingsRateCard
                    runwayCard
                }

                HStack(alignment: .top, spacing: 14) {
                    netWorthChartCard
                    allocationCard.frame(width: 320)
                }

                HStack(alignment: .top, spacing: 14) {
                    cashFlowChartCard
                    topCategoriesCard.frame(width: 320)
                }

                upcomingRecurrencesCard
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .navigationTitle("Tableau de bord")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bonjour")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(DateFmt.monthYear.string(from: .now).capitalized)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
            }
            Spacer()
        }
    }

    // MARK: - KPIs

    private var netWorthCard: some View {
        Card {
            let nw = AnalyticsEngine.netWorth(store)
            let assets = AnalyticsEngine.assets(store)
            let liab   = AnalyticsEngine.liabilities(store)
            StatLabel(
                label: "Patrimoine net",
                value: Money.format(nw),
                tint: nw >= 0 ? .primary : Theme.negative,
                caption: "\(Money.compact(assets)) actifs · \(Money.compact(liab)) passifs"
            )
        }
    }

    private var cashFlowCard: some View {
        Card {
            let cf = AnalyticsEngine.currentMonthCashFlow(store.transactions)
            let net = cf.income - cf.expense
            StatLabel(
                label: "Cash-flow du mois",
                value: Money.format(net, signed: true),
                tint: net >= 0 ? Theme.positive : Theme.negative,
                caption: "\(Money.compact(cf.income)) entrées · \(Money.compact(cf.expense)) sorties"
            )
        }
    }

    private var savingsRateCard: some View {
        Card {
            let cf = AnalyticsEngine.currentMonthCashFlow(store.transactions)
            let rate = AnalyticsEngine.savingsRate(income: cf.income, expense: cf.expense)
            StatLabel(
                label: "Taux d'épargne",
                value: rate.map { Pct.format($0) } ?? "—",
                tint: (rate ?? 0) >= 0.2 ? Theme.positive : ((rate ?? 0) >= 0 ? .primary : Theme.negative),
                caption: "Cible recommandée : 20 %"
            )
        }
    }

    private var runwayCard: some View {
        Card {
            let runway = AnalyticsEngine.runwayMonths(store)
            let value: String = {
                guard let r = runway else { return "—" }
                if r > 999 { return "∞" }
                return String(format: "%.1f mois", r)
            }()
            StatLabel(
                label: "Runway",
                value: value,
                tint: (runway ?? 0) >= 6 ? Theme.positive : ((runway ?? 0) >= 3 ? Theme.warning : Theme.negative),
                caption: "Liquidités / dépenses moyennes"
            )
        }
    }

    // MARK: - Charts

    private var netWorthChartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Patrimoine — projection 12 mois")
                let points = ForecastEngine.project(store, months: 12)
                Chart(points) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Net", p.netWorth))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", p.date), y: .value("Net", p.netWorth))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(Money.compact(d)).font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var allocationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Allocation d'actifs")
                let alloc = AnalyticsEngine.allocation(store).filter { $0.0 != .liability }
                let total = alloc.reduce(0) { $0 + $1.1 }
                if alloc.isEmpty {
                    EmptyStateView(
                        systemImage: "chart.pie",
                        title: "Aucun actif",
                        subtitle: "Ajoute des comptes pour voir ta répartition."
                    )
                } else {
                    Chart(alloc, id: \.0) { item in
                        SectorMark(
                            angle: .value("Valeur", item.1),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(item.0.color)
                        .cornerRadius(4)
                    }
                    .frame(height: 160)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(alloc, id: \.0) { item in
                            HStack(spacing: 8) {
                                Circle().fill(item.0.color).frame(width: 8, height: 8)
                                Text(item.0.label).font(.system(size: 12))
                                Spacer()
                                Text(total > 0 ? Pct.format(item.1 / total, fractionDigits: 0) : "—")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }

    private var cashFlowChartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Cash-flow — 6 derniers mois")
                let series = AnalyticsEngine.monthlyCashFlow(store.transactions, months: 6)
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("Mois", item.date, unit: .month),
                            y: .value("Revenus", item.income)
                        )
                        .foregroundStyle(Theme.positive)
                        .position(by: .value("Type", "Revenus"))

                        BarMark(
                            x: .value("Mois", item.date, unit: .month),
                            y: .value("Dépenses", item.expense)
                        )
                        .foregroundStyle(Theme.negative)
                        .position(by: .value("Type", "Dépenses"))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(Money.compact(d)).font(.system(size: 10))
                            }
                        }
                    }
                }
                .frame(height: 220)

                HStack(spacing: 12) {
                    legendDot(color: Theme.positive, label: "Revenus")
                    legendDot(color: Theme.negative, label: "Dépenses")
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var topCategoriesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Top dépenses du mois")
                let items = AnalyticsEngine.currentMonthByCategory(store.transactions, categories: store.categories).prefix(6)
                if items.isEmpty {
                    Text("Pas encore de dépense ce mois-ci.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    let max = items.map(\.total).max() ?? 1
                    VStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 10) {
                                Image(systemName: item.category?.systemImage ?? "questionmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(item.category?.color ?? .secondary)
                                    .frame(width: 18)
                                Text(item.category?.name ?? "Sans catégorie")
                                    .font(.system(size: 12))
                                Spacer()
                                Text(Money.compact(item.total))
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            ProgressView(value: item.total / max)
                                .progressViewStyle(.linear)
                                .tint(item.category?.color ?? Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private var upcomingRecurrencesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Prochaines échéances")
                let upcoming = store.recurrences
                    .filter { $0.isActive }
                    .prefix(5)
                if upcoming.isEmpty {
                    Text("Aucune récurrence définie. Ajoute ton salaire ou un abonnement pour voir tes prévisions s'animer.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(upcoming), id: \.id) { r in
                        HStack {
                            Image(systemName: r.kind == .income ? "arrow.down.circle" : "arrow.up.circle")
                                .foregroundStyle(r.kind == .income ? Theme.positive : Theme.negative)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.system(size: 13, weight: .medium))
                                Text("\(r.frequency.label) · \(DateFmt.short.string(from: r.nextDate))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((r.kind == .income ? "+ " : "− ") + Money.format(r.amount))
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(r.kind == .income ? Theme.positive : Theme.negative)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
