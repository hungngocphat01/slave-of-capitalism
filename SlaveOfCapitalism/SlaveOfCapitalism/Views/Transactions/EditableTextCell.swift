import SwiftUI

struct EditableTextCell: View {
    let value: String
    let isEditing: Bool
    @Binding var editText: String
    var alignment: Alignment = .leading
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    var font: Font = .body
    let onBeginEdit: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused($isFocused)
                    .onSubmit {
                        // Don't call onCommit directly — just remove focus.
                        // The onChange(of: isFocused) handler below is the single commit path.
                        isFocused = false
                    }
                    .onExitCommand {
                        onCancel()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            onCommit(editText)
                        }
                    }
                    .onAppear {
                        isFocused = true
                    }
            } else {
                Text(value)
                    .font(font)
                    .foregroundStyle(foregroundStyle)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        onBeginEdit()
                    })
            }
        }
    }
}
