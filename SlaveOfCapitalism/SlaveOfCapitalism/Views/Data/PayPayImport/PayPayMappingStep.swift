import SwiftUI

struct PayPayMappingStep: View {
    let rows: [TransformedRow]
    @Binding var walletMapping: [String: Int]
    let wallets: [WalletWithBalance]

    private var uniqueWalletNames: [String] {
        Array(Set(rows.map(\.wallet))).sorted()
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Map Payment Methods to Wallets")
                .font(.title2)

            List(uniqueWalletNames, id: \.self) { name in
                HStack {
                    Text(name)
                        .frame(width: 200, alignment: .leading)
                    Picker("", selection: binding(for: name)) {
                        Text("Unmapped").tag(0)
                        ForEach(wallets) { wallet in
                            Text("\(wallet.emoji ?? "") \(wallet.name)").tag(wallet.id)
                        }
                    }
                    .frame(width: 200)
                }
            }
        }
        .padding()
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
