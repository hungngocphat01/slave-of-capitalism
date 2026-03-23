import Charts
import SwiftUI

private struct DailyUsagePoint: Identifiable {
    let day: Int
    let categoryId: Int
    let categoryName: String
    let colorHex: String?
    let cumulative: Double

    var id: String { "\(categoryId)-\(day)" }
}

struct DailyUsageChart: View {
    let dailySummary: DailySummaryResponse?
    let totalBudget: Decimal
    let isLoading: Bool

    private var points: [DailyUsagePoint] {
        guard let dailySummary else { return [] }

        let daysToShow = visibleDayCount(for: dailySummary)
        let categories = dailySummary.categories
            .map { category -> (DailyCategoryData, total: Double) in
                let total = category.dailyAmounts.prefix(daysToShow).reduce(0, +)
                return (category, total)
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }

        var result: [DailyUsagePoint] = []
        result.reserveCapacity(categories.count * max(daysToShow, 1))

        for (category, _) in categories {
            var runningTotal = 0.0
            for day in 1...daysToShow {
                runningTotal += day <= category.dailyAmounts.count ? category.dailyAmounts[day - 1] : 0
                result.append(
                    DailyUsagePoint(
                        day: day,
                        categoryId: category.categoryId,
                        categoryName: category.categoryName,
                        colorHex: category.color,
                        cumulative: runningTotal
                    )
                )
            }
        }

        return result
    }

    private var budgetLineValue: Double {
        let value = NSDecimalNumber(decimal: totalBudget).doubleValue
        return value > 0 ? value : 0
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chart...")
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else if dailySummary == nil || points.isEmpty {
                ContentUnavailableView(
                    "No Chart Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("No spending data for this period yet.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Day", point.day),
                            y: .value("Cumulative", point.cumulative),
                            stacking: .standard
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color(from: point.colorHex).opacity(0.72))

                        LineMark(
                            x: .value("Day", point.day),
                            y: .value("Cumulative", point.cumulative)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(color(from: point.colorHex).opacity(0.9))
                    }

                    if budgetLineValue > 0 {
                        RuleMark(y: .value("Budget", budgetLineValue))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .annotation(position: .topLeading, alignment: .leading) {
                                Text("Budget \(Formatters.currency(totalBudget))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.background.opacity(0.9), in: Capsule())
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8))
                }
                .chartPlotStyle { plot in
                    plot
                        .background(.quaternary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
    }

    private func visibleDayCount(for summary: DailySummaryResponse) -> Int {
        var daysToShow = summary.daysInMonth

        let now = Date()
        let currentYear = Calendar.current.component(.year, from: now)
        let currentMonth = Calendar.current.component(.month, from: now)

        if summary.year == currentYear, summary.month == currentMonth {
            let today = Calendar.current.component(.day, from: now)
            daysToShow = min(summary.daysInMonth, today)
        }

        return max(daysToShow, 1)
    }

    private func color(from hex: String?) -> Color {
        guard let hex else { return .gray }

        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (r, g, b) = (
                ((int >> 8) & 0xF) * 17,
                ((int >> 4) & 0xF) * 17,
                (int & 0xF) * 17
            )
        case 6:
            (r, g, b) = (
                (int >> 16) & 0xFF,
                (int >> 8) & 0xFF,
                int & 0xFF
            )
        default:
            return .gray
        }

        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

#Preview {
    DailyUsageChart(dailySummary: nil, totalBudget: 0, isLoading: false)
        .padding()
}
