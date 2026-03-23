import SwiftUI

struct SummaryView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(AppSettings.self) private var appSettings

    @State private var summaryViewModel: SummaryViewModel?
    @State private var budgetViewModel: BudgetViewModel?
    @State private var expandedCategoryIds: Set<Int> = []
    @State private var editingCategoryId: Int?
    @State private var editBudgetValue = ""

    var body: some View {
        Group {
            if let summaryViewModel, let budgetViewModel {
                content(summaryViewModel: summaryViewModel, budgetViewModel: budgetViewModel)
            } else {
                ProgressView("Loading summary...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        initializeViewModelsIfNeeded()
                    }
            }
        }
        .navigationTitle("Summary")
    }

    @ViewBuilder
    private func content(summaryViewModel: SummaryViewModel, budgetViewModel: BudgetViewModel) -> some View {
        @Bindable var bindableSummary = summaryViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MonthYearPicker(year: $bindableSummary.year, month: $bindableSummary.month)

                if let errorMessage = combinedErrorMessage(summaryError: summaryViewModel.error, budgetError: budgetViewModel.error) {
                    errorBanner(message: errorMessage) {
                        Task {
                            await reload(summaryViewModel: summaryViewModel, budgetViewModel: budgetViewModel)
                        }
                    }
                }

                if summaryViewModel.isLoading, summaryViewModel.monthlySummary == nil {
                    ProgressView("Loading summary...")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let monthlySummary = summaryViewModel.monthlySummary {
                    budgetOverview(summaryViewModel: summaryViewModel, budgetViewModel: budgetViewModel, summary: monthlySummary)
                    chartSection(summaryViewModel: summaryViewModel, summary: monthlySummary)
                } else {
                    ContentUnavailableView(
                        "No Summary Data",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("No summary data for this month.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await reload(summaryViewModel: summaryViewModel, budgetViewModel: budgetViewModel)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(summaryViewModel.isLoading || budgetViewModel.isLoading || budgetViewModel.isMutating)
            }
        }
        .task(id: summaryViewModel.monthKey) {
            await reload(summaryViewModel: summaryViewModel, budgetViewModel: budgetViewModel)
        }
    }

    private func budgetOverview(
        summaryViewModel: SummaryViewModel,
        budgetViewModel: BudgetViewModel,
        summary: MonthlySummaryResponse
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget Overview")
                .font(.headline)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow(periodBoundaries: summary.periodBoundaries)

                    Divider()

                    ForEach(summary.categories) { category in
                        categoryRow(summaryViewModel: summaryViewModel, budgetViewModel: budgetViewModel, category: category)
                        if expandedCategoryIds.contains(category.id), !category.subcategories.isEmpty {
                            ForEach(category.subcategories) { subcategory in
                                subcategoryRow(subcategory, periods: subcategory.periods)
                            }
                        }
                        Divider()
                    }

                    totalRow(summary: summary)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func chartSection(summaryViewModel: SummaryViewModel, summary: MonthlySummaryResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Cumulative Usage")
                .font(.headline)
            DailyUsageChart(
                dailySummary: summaryViewModel.dailySummary,
                totalBudget: summary.totalBudget,
                isLoading: summaryViewModel.isLoading
            )
        }
    }

    private func headerRow(periodBoundaries: [Int]) -> some View {
        HStack(spacing: 12) {
            Text("Category")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 280, alignment: .leading)
            Text("Budget")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text("Actual")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text("%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            ForEach(periodBoundaries, id: \.self) { boundary in
                Text("\(boundary)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }

    private func categoryRow(
        summaryViewModel: SummaryViewModel,
        budgetViewModel: BudgetViewModel,
        category: CategorySummary
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            categoryColumn(summaryViewModel: summaryViewModel, category: category)
                .frame(width: 280, alignment: .leading)

            budgetCell(budgetViewModel: budgetViewModel, category: category)
                .frame(width: 120, alignment: .trailing)

            Text(formatAmount(category.actual))
                .frame(width: 120, alignment: .trailing)

            percentageCell(summaryViewModel: summaryViewModel, percentage: category.percentage)
                .frame(width: 80, alignment: .trailing)

            ForEach(Array(category.periods.enumerated()), id: \.offset) { _, value in
                periodCell(value)
            }
        }
        .padding(.vertical, 8)
    }

    private func subcategoryRow(_ subcategory: SubcategorySummary, periods: [Double]) -> some View {
        HStack(spacing: 12) {
            Text(subcategory.subcategoryName)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
                .frame(width: 280, alignment: .leading)

            Text("-")
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)

            Text(formatAmount(subcategory.actual))
                .frame(width: 120, alignment: .trailing)

            Text("-")
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            ForEach(Array(periods.enumerated()), id: \.offset) { _, value in
                periodCell(value)
            }
        }
        .padding(.vertical, 6)
    }

    private func totalRow(summary: MonthlySummaryResponse) -> some View {
        let totalBudgetValue = NSDecimalNumber(decimal: summary.totalBudget).doubleValue
        let totalActualValue = NSDecimalNumber(decimal: summary.totalActual).doubleValue
        let percentage = totalBudgetValue > 0 ? (totalActualValue / totalBudgetValue) * 100 : 0
        let threshold = thresholdColor(for: threshold(for: percentage))

        return HStack(spacing: 12) {
            Text("Total")
                .fontWeight(.semibold)
                .frame(width: 280, alignment: .leading)

            Text(formatAmount(totalBudgetValue))
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .trailing)

            Text(formatAmount(totalActualValue))
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .trailing)

            Text(percentage > 0 ? Formatters.percentage(percentage) : "-")
                .fontWeight(.semibold)
                .foregroundStyle(threshold)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    private func categoryColumn(summaryViewModel: SummaryViewModel, category: CategorySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if !category.subcategories.isEmpty {
                    Button {
                        toggleCategory(category.id)
                    } label: {
                        Image(systemName: expandedCategoryIds.contains(category.id) ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 12, height: 12)
                }

                Text(categoryTitle(for: category))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            ProgressView(value: min(category.percentage, 100), total: 100)
                .tint(thresholdColor(for: summaryViewModel.threshold(for: category.percentage)))
                .progressViewStyle(.linear)
        }
    }

    private func budgetCell(budgetViewModel: BudgetViewModel, category: CategorySummary) -> some View {
        Group {
            if editingCategoryId == category.categoryId {
                HStack(spacing: 6) {
                    TextField("Amount", text: $editBudgetValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                    Button {
                        Task {
                            await saveBudget(categoryId: category.categoryId, budgetViewModel: budgetViewModel)
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        cancelBudgetEdit()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                if category.categoryId > 0 {
                    if category.budget > 0 {
                        Button {
                            beginBudgetEdit(categoryId: category.categoryId, currentBudget: category.budget)
                        } label: {
                            Text(formatAmount(category.budget))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button("Create Budget") {
                            beginBudgetEdit(categoryId: category.categoryId, currentBudget: 0)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Text(formatAmount(category.budget))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func percentageCell(summaryViewModel: SummaryViewModel, percentage: Double) -> some View {
        let threshold = summaryViewModel.threshold(for: percentage)
        return Text(percentage > 0 ? Formatters.percentage(percentage) : "-")
            .foregroundStyle(thresholdColor(for: threshold))
    }

    private func periodCell(_ amount: Double) -> some View {
        Text(amount > 0 ? formatAmount(amount) : "")
            .foregroundStyle(.secondary)
            .frame(width: 84, alignment: .trailing)
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .foregroundStyle(.red)
            Spacer()
            Button("Retry", action: retry)
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func initializeViewModelsIfNeeded() {
        guard summaryViewModel == nil, budgetViewModel == nil else { return }
        summaryViewModel = SummaryViewModel(apiClient: apiClient)
        budgetViewModel = BudgetViewModel(apiClient: apiClient)
    }

    private func reload(summaryViewModel: SummaryViewModel, budgetViewModel: BudgetViewModel) async {
        await summaryViewModel.load()
        await budgetViewModel.load(year: summaryViewModel.year, month: summaryViewModel.month)
    }

    private func toggleCategory(_ categoryId: Int) {
        if expandedCategoryIds.contains(categoryId) {
            expandedCategoryIds.remove(categoryId)
        } else {
            expandedCategoryIds.insert(categoryId)
        }
    }

    private func beginBudgetEdit(categoryId: Int, currentBudget: Double) {
        editingCategoryId = categoryId
        editBudgetValue = currentBudget > 0 ? decimalString(from: currentBudget) : ""
    }

    private func cancelBudgetEdit() {
        editingCategoryId = nil
        editBudgetValue = ""
    }

    private func saveBudget(categoryId: Int, budgetViewModel: BudgetViewModel) async {
        guard categoryId > 0 else {
            cancelBudgetEdit()
            return
        }

        guard let amount = parseDecimal(editBudgetValue), amount >= 0 else {
            budgetViewModel.error = .validationError("Please enter a valid non-negative amount.")
            return
        }

        let success: Bool
        if let existing = budgetViewModel.budget(for: categoryId) {
            success = await budgetViewModel.update(id: existing.id, amount: amount)
        } else {
            success = await budgetViewModel.create(categoryId: categoryId, amount: amount)
        }

        guard success else { return }

        cancelBudgetEdit()
        if let summaryViewModel {
            await summaryViewModel.load()
        }
    }

    private func combinedErrorMessage(summaryError: APIError?, budgetError: APIError?) -> String? {
        if let budgetError {
            return budgetError.localizedDescription
        }
        if let summaryError {
            return summaryError.localizedDescription
        }
        return nil
    }

    private func threshold(for percentage: Double) -> SummaryViewModel.UsageThreshold {
        if percentage == 0 {
            return .neutral
        }
        if percentage < 90 {
            return .safe
        }
        if percentage <= 110 {
            return .warning
        }
        return .danger
    }

    private func thresholdColor(for threshold: SummaryViewModel.UsageThreshold) -> Color {
        switch threshold {
        case .neutral:
            return .secondary
        case .safe:
            return .green
        case .warning:
            return .yellow
        case .danger:
            return .red
        }
    }

    private func categoryTitle(for category: CategorySummary) -> String {
        if let emoji = category.emoji, !emoji.isEmpty {
            return "\(emoji) \(category.categoryName)"
        }
        return category.categoryName
    }

    private func parseDecimal(_ text: String) -> Decimal? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func decimalString(from value: Double) -> String {
        let decimalValue = Decimal(value)
        return NSDecimalNumber(decimal: decimalValue).stringValue
    }

    private func formatAmount(_ value: Double) -> String {
        Formatters.currency(
            Decimal(value),
            symbol: appSettings.currency,
            decimals: appSettings.decimals
        )
    }
}

#Preview {
    SummaryView()
}
