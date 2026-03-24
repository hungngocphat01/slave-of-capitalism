import Charts
import SwiftUI

private struct DailyUsagePoint: Identifiable {
    let day: Int
    let categoryId: Int
    let categoryName: String
    let colorHex: String?
    let cumulative: Double

    var id: String { "\(categoryId)-\(day)" }
    var seriesKey: String { categoryName }
}

struct DailyUsageChart: View {
    let dailySummary: DailySummaryResponse?
    let totalBudget: Decimal
    let isLoading: Bool

    @State private var hoveredDay: Int?

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

    private var colorDomain: [String] {
        points.reduce(into: [String]()) { result, point in
            if !result.contains(point.seriesKey) {
                result.append(point.seriesKey)
            }
        }
    }

    private var colorRange: [Color] {
        colorDomain.map { name in
            if let point = points.first(where: { $0.seriesKey == name }) {
                return color(from: point.colorHex)
            }
            return .gray
        }
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
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("Category", point.seriesKey))
                    }

                    if let hoveredDay {
                        RuleMark(x: .value("Day", hoveredDay))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 0.5))
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
                .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
                .chartLegend(.hidden)
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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotFrame = geo[proxy.plotFrame!]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let x = location.x - plotFrame.origin.x
                                    if let rawDay: Double = proxy.value(atX: x) {
                                        let day = Int(rawDay.rounded())
                                        let daysToShow = dailySummary.map { visibleDayCount(for: $0) } ?? 1
                                        let clamped = max(1, min(day, daysToShow))
                                        if clamped != hoveredDay {
                                            hoveredDay = clamped
                                        }
                                    }
                                case .ended:
                                    hoveredDay = nil
                                }
                            }

                        if let hoveredDay {
                            let rawDay = Double(hoveredDay)
                            if let xPos: CGFloat = proxy.position(forX: rawDay) {
                                let absX = xPos + plotFrame.origin.x
                                let midX = plotFrame.midX
                                let tooltipOffset: CGFloat = absX > midX ? -80 : 80
                                hoverTooltip(for: hoveredDay)
                                    .fixedSize()
                                    .position(
                                        x: absX + tooltipOffset,
                                        y: plotFrame.origin.y + 16
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
    }

    @ViewBuilder
    private func hoverTooltip(for day: Int) -> some View {
        let dayPoints = points
            .filter { $0.day == day && $0.cumulative > 0 }
            .sorted { $0.cumulative > $1.cumulative }

        VStack(alignment: .leading, spacing: 4) {
            Text("Day \(day)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(dayPoints) { point in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(from: point.colorHex))
                        .frame(width: 8, height: 8)
                    Text(point.categoryName)
                        .font(.caption)
                    Spacer(minLength: 8)
                    Text(Formatters.currency(Decimal(point.cumulative), symbol: "\u{00A5}", decimals: 0))
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
