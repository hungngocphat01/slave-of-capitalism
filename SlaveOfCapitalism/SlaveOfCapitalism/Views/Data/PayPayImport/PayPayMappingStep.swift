import SwiftUI

struct PayPayMappingStep: View {
    let rows: [TransformedRow]
    @Binding var walletMapping: [String: Int]
    let wallets: [WalletWithBalance]

    private var uniqueWalletNames: [String] {
        Array(Set(rows.map(\.wallet))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                Text("Map Wallets")
                    .font(.title2.weight(.semibold))
                Text("Assign each PayPay payment method to a wallet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            List(uniqueWalletNames, id: \.self) { name in
                HStack {
                    Text(name)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("", selection: binding(for: name)) {
                        Text("Unmapped").tag(0)
                        ForEach(wallets) { wallet in
                            Text("\(wallet.emoji ?? "") \(wallet.name)").tag(wallet.id)
                        }
                    }
                    .frame(width: 220)
                }
            }
        }
        .padding(.horizontal)
    }

    private func binding(for walletName: String) -> Binding<Int> {
        Binding(
            get: { walletMapping[walletName] ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    walletMapping.removeValue(forKey: walletName)
                } else {
                    walletMapping[walletName] = newValue
                }
            }
        )
    }
}
