import SwiftUI

struct PayPayConfirmStep: View {
    let transactionCount: Int
    let transferCount: Int
    let result: BulkImportResponse?
    let transfersImported: Int
    let error: String?
    let isImporting: Bool

    var body: some View {
        VStack(spacing: 20) {
            if let result {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Import Complete")
                    .font(.title2)
                Text("\(result.importedCount) transactions imported")
                    .foregroundStyle(.secondary)
                if transfersImported > 0 {
                    Text("\(transfersImported) wallet transfers created")
                        .foregroundStyle(.secondary)
                }
            } else if let error {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Import Failed")
                    .font(.title2)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if isImporting {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Importing...")
                    .font(.title2)
            } else {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Ready to Import")
                    .font(.title2)
                if transactionCount > 0 {
                    Text("\(transactionCount) transactions will be imported")
                        .foregroundStyle(.secondary)
                }
                if transferCount > 0 {
                    Text("\(transferCount) wallet transfers will be created")
                        .foregroundStyle(.secondary)
                }
                if transactionCount == 0 && transferCount == 0 {
                    Text("No items to import")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
