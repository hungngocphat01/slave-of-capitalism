import SwiftUI

struct ConfirmationDialog: View {
    let title: String
    let message: String
    let confirmButtonTitle: String
    var isDestructive = true
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(confirmButtonTitle, role: isDestructive ? .destructive : nil, action: onConfirm)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}
