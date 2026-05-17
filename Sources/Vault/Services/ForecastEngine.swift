import Foundation

/// Projects net worth into the future from active recurrences.
///
/// The model is deliberately simple and explicit:
/// - We walk month-by-month from "now" to `now + months`.
/// - Inside each month, we iterate every active recurrence and apply its
///   amount the right number of times for that month's window.
/// - One-off (non-recurring) transactions are **not** extrapolated — they
///   represent past reality, not a stable signal we should project.
///
/// The output is a series of monthly `Point`s, suitable for plotting directly
/// with Swift Charts.
struct ForecastEngine {

    /// One projected month-end snapshot.
    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let netWorth: Double
        let cumulativeIncome: Double
        let cumulativeExpense: Double
    }

    /// Build a monthly projection of net worth.
    ///
    /// - Parameters:
    ///   - store: Current state — provides starting net worth and recurrence rules.
    ///   - months: Horizon length in months (e.g. 12, 24, 60).
    ///   - now: Override for "today" — useful for tests.
    /// - Returns: `months + 1` points, starting at `(now, netWorth)`.
    @MainActor
    static func project(_ store: Store, months: Int, now: Date = .now) -> [Point] {
        let cal = Calendar.current
        var points: [Point] = []

        let initialNet = AnalyticsEngine.netWorth(store)
        var runningNet = initialNet
        var cumIn = 0.0
        var cumOut = 0.0

        // Anchor: today's snapshot
        points.append(Point(
            date: now,
            netWorth: runningNet,
            cumulativeIncome: 0,
            cumulativeExpense: 0
        ))

        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return points
        }

        let recurrences = store.recurrences.filter { $0.isActive }

        for i in 1...months {
            guard let pStart = cal.date(byAdding: .month, value: i - 1, to: monthStart),
                  let pEnd   = cal.date(byAdding: .month, value: i,     to: monthStart) else { continue }

            // For the *current* month, only count future occurrences — the
            // ones earlier in the month should already be reflected in the
            // current balance.
            let windowStart = max(pStart, now)
            var monthIn = 0.0
            var monthOut = 0.0

            for r in recurrences {
                // Recurrence already ended → skip.
                if let endDate = r.endDate, endDate < windowStart { continue }

                var cursor = max(r.nextDate, r.startDate)
                let stop = min(pEnd, r.endDate ?? .distantFuture)
                var safety = 0
                while cursor < stop {
                    if cursor >= windowStart {
                        switch r.kind {
                        case .income:   monthIn  += r.amount
                        case .expense:  monthOut += r.amount
                        case .transfer: break // neutral for net worth
                        }
                    }
                    let next = r.frequency.nextDate(after: cursor)
                    // Defence-in-depth against a misconfigured cadence that
                    // doesn't advance the cursor — would otherwise loop.
                    if next <= cursor { break }
                    cursor = next
                    safety += 1
                    if safety > 600 { break }
                }
            }

            cumIn  += monthIn
            cumOut += monthOut
            runningNet += monthIn - monthOut

            points.append(Point(
                date: pEnd,
                netWorth: runningNet,
                cumulativeIncome: cumIn,
                cumulativeExpense: cumOut
            ))
        }

        return points
    }
}
