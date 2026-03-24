import SwiftUI

struct PayPayConfirmStep: View {
    let transactionCount: Int
    let transferCount: Int
    let result: BulkImportResponse?
    let transfersImported: Int
    let error: String?
    let isImporting: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let result {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.green)
                    .padding(.bottom, 4)
                Text("Import Complete")
                    .font(.title2.weight(.semibold))
                VStack(spacing: 4) {
                    Text("\(result.importedCount) transactions imported")
                    if transfersImported > 0 {
                        Text("\(transfersImported) wallet transfers created")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else if let error {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.red)
                    .padding(.bottom, 4)
                Text("Import Failed")
                    .font(.title2.weight(.semibold))
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            } else if isImporting {
                ProgressView()
                    .controlSize(.large)
                    .padding(.bottom, 4)
                Text("Importing\u{2026}")
                    .font(.title2.weight(.semibold))
                Text("Please wait while your data is uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 4)
                Text("Ready to Import")
                    .font(.title2.weight(.semibold))
                VStack(spacing: 4) {
                    if transactionCount > 0 {
                        Text("\(transactionCount) transactions will be imported")
                    }
                    if transferCount > 0 {
                        Text("\(transferCount) wallet transfers will be created")
                    }
                    if transactionCount == 0 && transferCount == 0 {
                        Text("No items to import")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
