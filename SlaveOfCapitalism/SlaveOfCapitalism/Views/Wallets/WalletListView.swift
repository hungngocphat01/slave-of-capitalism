import SwiftUI

private enum WalletSheetDestination: Identifiable {
    case add
    case edit(WalletWithBalance)
    case transfer(WalletWithBalance)
    case calibrate(WalletWithBalance)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let wallet):
            return "edit-\(wallet.id)"
        case .transfer(let wallet):
            return "transfer-\(wallet.id)"
        case .calibrate(let wallet):
            return "calibrate-\(wallet.id)"
        }
    }
}

struct WalletListView: View {
    @Environment(CategoryStore.self) private var categoryStore

    @State private var viewModel: WalletViewModel
    @State private var sheetDestination: WalletSheetDestination?
    @State private var walletPendingDeletion: WalletWithBalance?
    @State private var didLoad = false

    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
        _viewModel = State(initialValue: WalletViewModel(apiClient: apiClient))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summarySection

                if let error = viewModel.error {
                    errorSection(message: error.localizedDescription)
                }

                if viewModel.isLoading && viewModel.wallets.isEmpty {
                    ProgressView("Loading wallets...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 32)
                } else if viewModel.wallets.isEmpty {
                    ContentUnavailableView(
                        "No Wallets",
                        systemImage: "wallet.bifold",
                        description: Text("Create a wallet to start tracking balances.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                        ForEach(viewModel.wallets) { wallet in
                            WalletCard(wallet: wallet)
                                .contextMenu {
                                    Button("Edit") {
                                        sheetDestination = .edit(wallet)
                                    }

                                    Button("Transfer") {
                                        sheetDestination = .transfer(wallet)
                                    }

                                    Button("Calibrate") {
                                        sheetDestination = .calibrate(wallet)
                                    }

                                    Divider()

                                    Button("Delete", role: .destructive) {
                                        walletPendingDeletion = wallet
                                    }
                                }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Wallets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheetDestination = .add
                } label: {
                    Label("Add Wallet", systemImage: "plus")
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await viewModel.load()
        }
        .alert(
            "Delete Wallet?",
            isPresented: Binding(
                get: { walletPendingDeletion != nil },
                set: { newValue in
                    if !newValue {
                        walletPendingDeletion = nil
                    }
                }
            ),
            presenting: walletPendingDeletion
        ) { wallet in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteWallet(id: wallet.id)
                    walletPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                walletPendingDeletion = nil
            }
        } message: { wallet in
            Text("This will permanently delete \(wallet.name).")
        }
        .sheet(item: $sheetDestination) { destination in
            switch destination {
            case .add:
                WalletFormSheet(apiClient: apiClient) {
                    await viewModel.load()
                }
            case .edit(let wallet):
                WalletFormSheet(apiClient: apiClient, wallet: wallet) {
                    await viewModel.load()
                }
            case .transfer(let wallet):
                TransferSheet(apiClient: apiClient, wallets: viewModel.wallets, initialFromWalletId: wallet.id) {
                    await viewModel.load()
                }
            case .calibrate(let wallet):
                CalibrateSheet(apiClient: apiClient, wallet: wallet, categories: categoryStore.categories) {
                    await viewModel.load()
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                WalletSummaryCard(title: "Available Credit", value: Formatters.currency(viewModel.totalAvailableCredit), tint: .blue)
                WalletSummaryCard(title: "Credit Used", value: Formatters.currency(viewModel.totalCreditUsed), tint: .orange)
                WalletSummaryCard(title: "Net Position", value: Formatters.currency(viewModel.netPosition), tint: viewModel.netPosition < 0 ? .red : .green)
            }
        }
    }

    private func errorSection(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Retry") {
                Task {
                    await viewModel.load()
                }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WalletSummaryCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
