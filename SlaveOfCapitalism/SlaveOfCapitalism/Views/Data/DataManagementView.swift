import SwiftUI

struct DataManagementView: View {
    @State private var showPayPayWizard = false

    var body: some View {
        List {
            Section("Import") {
                Button {
                    showPayPayWizard = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text("Import from PayPay CSV")
                                .font(.headline)
                            Text("Import transactions from PayPay CSV export")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            Section("Export") {
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Data Management")
        .sheet(isPresented: $showPayPayWizard) {
            PayPayWizardSheet()
        }
    }
}
