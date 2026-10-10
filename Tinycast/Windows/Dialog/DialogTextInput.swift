import SwiftUI

/// The name a save/rename dialog edits; reference semantics let the caller read it back.
@MainActor
@Observable
final class DialogTextState {
    var text: String

    init(_ text: String = "") {
        self.text = text
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmed.isEmpty && !trimmed.contains("\0") }
}

struct DialogTextInputFields: View {
    @Bindable var state: DialogTextState
    var prompt: String = "Name"
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $state.text, prompt: Text(prompt))
            .focused($focused)
            .dialogTextField()
            .onAppear { focused = true }
    }
}
