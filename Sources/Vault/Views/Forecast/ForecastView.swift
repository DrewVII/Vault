import SwiftUI
import Charts

/// Net-worth and cash-flow projection screen.
///
/// A horizon switcher (3 / 6 / 12 / 24 / 60 months) drives two charts:
/// 1. Projected net-worth trajectory (area + line).
/// 2. Cumulative income vs. cumulative expense (two lines).
///
/// Everything is recomputed live from `ForecastEngine.project(_:months:)`.
struct ForecastView: View {
    @EnvironmentObject private var store: Store
    @State private var months: Int = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                horizonPicker

                let points = ForecastEngine.project(store, months: months)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Patrimoine net projeté")
                        Chart(points) { p in
                            AreaMark(x: .value("Date", p.date), y: .value("Net", p.netWorth))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Theme.accent.opacity(0.4), Theme.accent.opacity(0.0)],
                                        startPoint: .top, endPoint: .bottom)
                                )
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Date", p.date), y: .value("Net", p.netWorth))
                                .foregroundStyle(Theme.accent)
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { v in
                                AxisGridLine().foregroundStyle(Theme.stroke)
                                AxisValueLabel {
                                    if let d = v.as(Double.self) {
                                        Text(Money.compact(d)).font(.system(size: 10))
                                    }
                                }
                            }
                        }
                        .frame(height: 280)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle("Cumul revenus / dépenses")
                            Chart(points) { p in
                                LineMark(x: .value("Date", p.date), y: .value("Revenus", p.cumulativeIncome))
                                    .foregroundStyle(Theme.positive)
                                    .interpolationMethod(.monotone)
                                LineMark(x: .value("Date", p.date), y: .value("Dépenses", p.cumulativeExpense))
                                    .foregroundStyle(Theme.negative)
                                    .interpolationMethod(.monotone)
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { v in
                                    AxisGridLine().foregroundStyle(Theme.stroke)
                                    AxisValueLabel {
                                        if let d = v.as(Double.self) {
                                            Text(Money.compact(d)).font(.system(size: 10))
                                        }
                                    }
                                }
                            }
                            .frame(height: 220)
                            HStack(spacing: 12) {
                                legendDot(color: Theme.positive, label: "Revenus cumulés")
                                legendDot(color: Theme.negative, label: "Dépenses cumulées")
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle("Synthèse")
                            if let last = points.last, let first = points.first {
                                let delta = last.netWorth - first.netWorth
                                row("Patrimoine actuel", Money.format(first.netWorth))
                                row("Dans \(months) mois", Money.format(last.netWorth))
                                row("Variation", Money.format(delta, signed: true), tint: delta >= 0 ? Theme.positive : Theme.negative)
                                row("Revenus cumulés", Money.format(last.cumulativeIncome), tint: Theme.positive)
                                row("Dépenses cumulées", Money.format(last.cumulativeExpense), tint: Theme.negative)
                            }
                            Spacer(minLength: 0)
                            Text("Hypothèse : seules les récurrences actives sont projetées. Les dépenses ponctuelles ne sont pas anticipées.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 320)
                }
            }
            .padding(24)
        }
        .background(Theme.canvas)
        .navigationTitle("Prévisions")
    }

    private var horizonPicker: some View {
        HStack(spacing: 8) {
            ForEach([3, 6, 12, 24, 60], id: \.self) { m in
                Button {
                    withAnimation(.snappy) { months = m }
                } label: {
                    Text(label(for: m))
                        .font(.system(size: 12, weight: months == m ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(months == m ? Theme.accent.opacity(0.18) : Color.clear)
                        )
                        .foregroundStyle(months == m ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func label(for months: Int) -> String {
        switch months {
        case 12: return "1 an"
        case 24: return "2 ans"
        case 60: return "5 ans"
        default: return "\(months) mois"
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(tint).monospacedDigit()
        }
    }
}
