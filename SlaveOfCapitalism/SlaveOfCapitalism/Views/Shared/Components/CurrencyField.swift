import SwiftUI

struct CurrencyField: View {
    let title: String
    @Binding var text: String
    var prompt: String?

    var body: some View {
        TextField(prompt ?? title, text: sanitizedText)
            .multilineTextAlignment(.trailing)
            .onKeyPress("k", phases: .down) { press in
                guard press.modifiers.contains(.command) else {
                    return .ignored
                }

                text = Self.sanitize(text + "000")
                return .handled
            }
    }

    private var sanitizedText: Binding<String> {
        Binding(
            get: { text },
            set: { text = Self.sanitize($0) }
        )
    }

    private static func sanitize(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        var result = ""
        var didUseSeparator = false

        for character in normalized {
            if character.isWholeNumber {
                result.append(character)
            } else if character == ".", !didUseSeparator {
                result.append(character)
                didUseSeparator = true
            }
        }

        return result
    }
}
