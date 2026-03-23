import SwiftUI

struct AuditView: View {
    @Environment(APIClient.self) private var apiClient

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
                List {
                    if let error = viewModel.error {
                        Section {
                            errorBanner(message: error.localizedDescription) {
                                Task {
                                    await viewModel.load()
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }

                    ForEach(viewModel.audits) { audit in
                        Section(Formatters.date(audit.date)) {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledContent("Balances") {
                                    Text(balanceSummary(for: audit))
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 24) {
                                    metric(title: "Debts", value: Formatters.currency(audit.debts))
                                    metric(title: "Owed", value: Formatters.currency(audit.owed))
                                    metric(title: "Net", value: Formatters.currency(audit.netPosition))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.inset)
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

    private func balanceSummary(for audit: BalanceAuditResponse) -> String {
        let items = audit.balances
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                "\(key): \(Formatters.currency(Decimal(value ?? 0), symbol: "¥", decimals: 0))"
            }

        if items.isEmpty {
            return "No balances recorded"
        }

        return items.joined(separator: "\n")
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
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
