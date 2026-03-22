import SwiftUI

struct WalletCard: View {
    let wallet: WalletWithBalance

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text(wallet.emoji ?? fallbackEmoji)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 6) {
                    Text(wallet.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(walletTypeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(wallet.walletType == .credit ? Color.orange : Color.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill((wallet.walletType == .credit ? Color.orange : Color.green).opacity(0.14))
                        }
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(wallet.walletType == .credit ? "Credit Used" : "Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(Formatters.currency(wallet.currentBalance))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(wallet.walletType == .credit ? Color.red : Color.primary)

                if wallet.walletType == .credit {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Formatters.currency(wallet.availableCredit ?? 0))
                                .font(.subheadline.weight(.medium))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Limit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Formatters.currency(wallet.creditLimit))
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var walletTypeLabel: String {
        switch wallet.walletType {
        case .normal:
            return "Normal"
        case .credit:
            return "Credit"
        }
    }

    private var fallbackEmoji: String {
        wallet.walletType == .credit ? "💳" : "💰"
    }
}
