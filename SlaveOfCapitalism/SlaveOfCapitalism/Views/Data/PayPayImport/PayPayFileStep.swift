import SwiftUI
import UniformTypeIdentifiers

struct PayPayFileStep: View {
    @Binding var csvContent: String?
    @Binding var rulesContent: String?
    @State private var showCSVPicker = false
    @State private var showRulesPicker = false
    @State private var csvFileName: String?
    @State private var rulesFileName: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header icon
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text("Select Files")
                .font(.title2.weight(.semibold))
            Text("Choose a PayPay CSV export and an optional rules file.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            // CSV file
            VStack(spacing: 12) {
                GroupBox {
                    HStack {
                        Image(systemName: csvContent != nil ? "checkmark.circle.fill" : "doc.badge.plus")
                            .foregroundStyle(csvContent != nil ? .green : .secondary)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PayPay CSV File")
                                .font(.headline)
                            Text(csvFileName ?? "No file selected")
                                .font(.subheadline)
                                .foregroundStyle(csvFileName == nil ? .secondary : .primary)
                        }
                        Spacer()
                        Button("Choose\u{2026}") { showCSVPicker = true }
                    }
                    .padding(4)
                }
                .fileImporter(
                    isPresented: $showCSVPicker,
                    allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText]
                ) { result in
                    if case .success(let url) = result {
                        csvFileName = url.lastPathComponent
                        _ = url.startAccessingSecurityScopedResource()
                        csvContent = try? String(contentsOf: url, encoding: .utf8)
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // Rules file
                GroupBox {
                    HStack {
                        Image(systemName: rulesContent != nil ? "checkmark.circle.fill" : "gearshape")
                            .foregroundStyle(rulesContent != nil ? .green : .secondary)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rules File")
                                .font(.headline)
                            Text(rulesFileName ?? "No file selected — optional")
                                .font(.subheadline)
                                .foregroundStyle(rulesFileName == nil ? .secondary : .primary)
                        }
                        Spacer()
                        if rulesContent != nil {
                            Button("Clear") {
                                rulesContent = nil
                                rulesFileName = nil
                            }
                        }
                        Button("Choose\u{2026}") { showRulesPicker = true }
                    }
                    .padding(4)
                }
                .fileImporter(
                    isPresented: $showRulesPicker,
                    allowedContentTypes: [UTType.json, UTType.plainText]
                ) { result in
                    if case .success(let url) = result {
                        rulesFileName = url.lastPathComponent
                        _ = url.startAccessingSecurityScopedResource()
                        rulesContent = try? String(contentsOf: url, encoding: .utf8)
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
            .frame(maxWidth: 460)

            Spacer()
            Spacer()
        }
        .padding()
    }
}
