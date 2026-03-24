import SwiftUI

struct AuditView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(WalletStore.self) private var walletStore

    @State private var viewModel: AuditViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                ProgressView("Loading snapshots...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        initializeViewModelIfNeeded()
                    }
            }
        }
        .navigationTitle("Audit")
    }

    @ViewBuilder
    private func content(for viewModel: AuditViewModel) -> some View {
        Group {
            if viewModel.isLoading && viewModel.audits.isEmpty {
                ProgressView("Loading snapshots...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.audits.isEmpty {
                ErrorView(
                    message: error.localizedDescription,
                    onRetry: {
                        Task {
                            await viewModel.load()
                        }
                    }
                )
            } else if viewModel.audits.isEmpty {
                ContentUnavailableView(
                    "No snapshots taken",
                    systemImage: "checkmark.shield",
                    description: Text("Take a balance snapshot to start tracking net position over time.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if let error = viewModel.error {
                            errorBanner(message: error.localizedDescription) {
                                Task { await viewModel.load() }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }

                        // Table header
                        auditHeaderRow
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        Divider().padding(.horizontal, 20)

                        // Snapshot rows
                        ForEach(viewModel.audits) { audit in
                            auditRow(for: audit)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.takeSnapshot()
                    }
                } label: {
                    if viewModel.isTakingSnapshot {
                        Label("Taking Snapshot...", systemImage: "hourglass")
                    } else {
                        Label("Take Snapshot", systemImage: "camera.metering.center.weighted")
                    }
                }
                .disabled(viewModel.isLoading || viewModel.isTakingSnapshot)
            }
        }
        .task {
            if viewModel.audits.isEmpty && !viewModel.isLoading {
                await viewModel.load()
            }
        }
    }

    private func initializeViewModelIfNeeded() {
        guard viewModel == nil else { return }
        viewModel = AuditViewModel(apiClient: apiClient)
    }

    private func walletName(for key: String) -> String {
        if let id = Int(key), let wallet = walletStore.wallet(for: id) {
            return wallet.name
        }
        return key
    }

    private var auditHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Date")
                .frame(width: 100, alignment: .leading)

            ForEach(walletColumns, id: \.self) { name in
                Text(name)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text("Debts")
                .frame(width: 80, alignment: .trailing)
            Text("Owed")
                .frame(width: 80, alignment: .trailing)
            Text("Net")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var walletColumns: [String] {
        guard let first = viewModel?.audits.first else { return [] }
        return first.balances.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { walletName(for: $0) }
    }

    private func auditRow(for audit: BalanceAuditResponse) -> some View {
        let sorted = audit.balances
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }

        return HStack(spacing: 0) {
            Text(Formatters.date(audit.date))
                .font(.subheadline.weight(.medium))
                .frame(width: 100, alignment: .leading)

            ForEach(sorted, id: \.key) { _, value in
                Text(Formatters.currency(Decimal(value ?? 0), symbol: "\u{00A5}", decimals: 0))
                    .font(.subheadline.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text(Formatters.currency(audit.debts))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(audit.debts > 0 ? .red : .secondary)
                .frame(width: 80, alignment: .trailing)
            Text(Formatters.currency(audit.owed))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(audit.owed > 0 ? .green : .secondary)
                .frame(width: 80, alignment: .trailing)
            Text(Formatters.currency(audit.netPosition))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 90, alignment: .trailing)
        }
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Retry", action: retry)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
