import SwiftUI

struct PayPayPreviewStep: View {
    let rows: [TransformedRow]
    @Binding var categoryMapping: [String: CategoryMapEntry]
    let categories: [CategoryWithSubcategories]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "tablecells")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                Text("Preview Transactions")
                    .font(.title2.weight(.semibold))
                Text("\(rows.count) transactions ready for review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            Table(rows) {
                TableColumn("Date", value: \.date)
                    .width(min: 80, ideal: 90)
                TableColumn("Description", value: \.description)
                    .width(min: 120, ideal: 200)
                TableColumn("Amount") { row in
                    Text(String(format: "%.0f", row.amount))
                        .foregroundStyle(row.direction == "inflow" ? .green : .primary)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Method", value: \.method)
                    .width(min: 80, ideal: 100)
                TableColumn("Category") { row in
                    Text(row.category ?? "—")
                        .foregroundStyle(row.category == nil ? .secondary : .primary)
                }
                .width(min: 80, ideal: 120)
            }
        }
        .padding(.horizontal)
    }
}
