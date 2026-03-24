import SwiftUI

struct DataManagementView: View {
    @State private var showPayPayWizard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Import section
            VStack(alignment: .leading, spacing: 12) {
                Text("Import")
                    .font(.title3.weight(.semibold))

                Button {
                    showPayPayWizard = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tint)
                        Text("PayPay CSV")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Export section
            VStack(alignment: .leading, spacing: 12) {
                Text("Export")
                    .font(.title3.weight(.semibold))

                Text("Coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("Data")
        .sheet(isPresented: $showPayPayWizard) {
            PayPayWizardSheet()
        }
    }
}
