import SwiftUI

/// A pop-up button that opens a searchable list instead of a menu — the
/// language table is long enough that scrolling it is worse than typing three
/// letters of the name.
struct LanguageField: View {
    /// How the closed control draws itself.
    enum Style {
        /// A pop-up button, for the main window's control row.
        case bordered
        /// Bare text and a chevron, for the overlay's cramped header.
        case inline
    }

    @Binding var selection: String
    /// Offers "Detect language" at the top, for the source side.
    var includesAutoDetect = false
    var width: CGFloat = 180
    var style: Style = .bordered
    /// Lets a host suppress its own dismissal while the list is open.
    var onPresentedChange: (Bool) -> Void = { _ in }

    @State private var isPresented = false
    @State private var query = ""
    @State private var hovered: String?
    @State private var isHovering = false
    @FocusState private var searchFocused: Bool

    /// Row height for `.inline`, so a label beside it can match.
    static let inlineHeight: CGFloat = 20

    var body: some View {
        control
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { picker }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    query = ""
                    searchFocused = true
                }
                onPresentedChange(presented)
            }
    }

    /// Announces the list before presenting it, not after. A host that hides
    /// itself when it loses key focus needs to know first: the popover takes
    /// focus as part of presenting, so a callback from `onChange` would arrive
    /// too late to stop it.
    private func present() {
        if !isPresented { onPresentedChange(true) }
        isPresented.toggle()
    }

    @ViewBuilder
    private var control: some View {
        switch style {
        case .bordered:
            Button { present() } label: {
                HStack(spacing: 6) {
                    Text(Languages.label(for: selection))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)

        case .inline:
            // Plain, not `.accessoryBar`: that style adds insets of its own, so
            // its label no longer sits at the same height as plain text beside
            // it. Here the affordance is the chevron plus a hover fill, and the
            // box is a fixed `Self.inlineHeight` so it lines up with anything
            // else in the row set to that height.
            Button { present() } label: {
                HStack(spacing: 3) {
                    Text(Languages.label(for: selection))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 5)
                .frame(height: Self.inlineHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovering || isPresented ? 0.09 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("Translate into a different language")
        }
    }

    private var picker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search languages", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { choose(first) } }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if includesAutoDetect, Languages.autoDetect.matchesAutoDetect(query) {
                        row(code: Languages.autoDetect, title: "Detect language", detail: nil)
                        Divider().padding(.vertical, 2)
                    }
                    ForEach(results) { language in
                        row(code: language.code, title: language.name, detail: language.native)
                    }
                    if results.isEmpty, !includesAutoDetect || !Languages.autoDetect.matchesAutoDetect(query) {
                        Text("No matches")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 260)
        }
        .frame(width: 270)
    }

    private var results: [Language] {
        Languages.all.filter { $0.matches(query) }
    }

    private func row(code: String, title: String, detail: String?) -> some View {
        let isSelected = code == selection
        let isHovered = code == hovered

        return Button { choose(code) } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let detail, detail != title {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(isHovered ? .white.opacity(0.7) : Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .onHover { hovered = $0 ? code : (hovered == code ? nil : hovered) }
    }

    private func choose(_ language: Language) { choose(language.code) }

    private func choose(_ code: String) {
        selection = code
        isPresented = false
    }
}

private extension String {
    /// "Detect language" should surface for the obvious queries.
    func matchesAutoDetect(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return "detect language auto".localizedCaseInsensitiveContains(query)
    }
}
