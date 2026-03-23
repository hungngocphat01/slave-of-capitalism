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
        VStack(spacing: 20) {
            Text("Select Files")
                .font(.title2)

            // CSV file
            GroupBox("PayPay CSV File (required)") {
                HStack {
                    Text(csvFileName ?? "No file selected")
                        .foregroundStyle(csvFileName == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose...") { showCSVPicker = true }
                }
                .padding(8)
            }

            // Rules file
            GroupBox("Rules File (optional)") {
                HStack {
                    Text(rulesFileName ?? "No file selected")
                        .foregroundStyle(rulesFileName == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose...") { showRulesPicker = true }
                    if rulesContent != nil {
                        Button("Clear") { rulesContent = nil; rulesFileName = nil }
                    }
                }
                .padding(8)
            }

            if csvContent != nil {
                Label("CSV loaded successfully", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding()
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
}
