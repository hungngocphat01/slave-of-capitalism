import SwiftUI

struct TransactionRow: View {
    let transaction: TransactionWithDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transaction.description?.isEmpty == false ? transaction.description! : "Untitled Transaction")
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(transaction.classification.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if transaction.isIgnored {
                    badge("Ignored", tint: .orange)
                }

                if transaction.hasLinkedEntry {
                    badge("Linked", tint: .blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
