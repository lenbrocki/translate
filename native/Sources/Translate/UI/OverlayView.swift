import SwiftUI

/// The floating translation card. Deliberately small and quiet: it appears over
/// whatever the user is reading, so it borrows the system HUD material rather
/// than painting a window of its own.
struct OverlayView: View {
    @Bindable var session: TranslationSession
    var onClose: () -> Void
    var onReplace: () -> Void
    var onOpenInApp: () -> Void
    /// The language list is a child window, so the panel resigns key while it
    /// is open. The host needs to know not to dismiss itself.
    var onPickerOpenChange: (Bool) -> Void = { _ in }

    @State private var contentHeight: CGFloat = 0
    @State private var didCopy = false
    @State private var isReplacePending = false

    private let width: CGFloat = 420
    private let maxBodyHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            body(for: session)
            Divider().opacity(0.4)
            footer
        }
        // The panel is reused, so a replace that never happened (the card was
        // dismissed first) must not still read "Replacing…" next time.
        .onChange(of: session.output.isEmpty) { _, isEmpty in
            if isEmpty { isReplacePending = false }
        }
        .frame(width: width)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            if session.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            }

            if session.request == nil, session.errorMessage != nil {
                Text("Couldn't translate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: LanguageField.inlineHeight)
            } else {
                // Everything in this row is the same height, so centring the
                // boxes centres the glyphs too.
                Text(sourceLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: LanguageField.inlineHeight)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(height: LanguageField.inlineHeight)

                LanguageField(
                    selection: targetLanguage,
                    style: .inline,
                    onPresentedChange: onPickerOpenChange
                )
            }

            Spacer(minLength: 8)

            OverlayButton(symbol: "xmark", help: "Close (⎋)", action: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: sourceLabel)
    }

    /// The actions live below the translation rather than beside the
    /// languages, which leaves the header room for long language names.
    private var footer: some View {
        HStack(spacing: 2) {
            OverlayButton(
                title: "Open in App",
                symbol: "macwindow",
                help: "Continue with this translation in the main window"
            ) {
                onOpenInApp()
            }
            .disabled(session.request == nil)

            Spacer(minLength: 8)

            OverlayButton(
                title: didCopy ? "Copied" : "Copy",
                symbol: didCopy ? "checkmark" : "doc.on.doc",
                help: "Copy the translation (⌘C)",
                action: copy
            )
            .disabled(session.trimmedOutput.isEmpty)

            OverlayButton(
                title: isReplacePending ? "Replacing…" : "Replace",
                symbol: "text.insert",
                help: "Replace the selection with the translation (⌘↩)"
            ) {
                isReplacePending = true
                onReplace()
            }
            .disabled(session.trimmedOutput.isEmpty || session.errorMessage != nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    /// The language actually detected, or the one the user pinned.
    private var sourceLabel: String {
        if let detected = session.detectedLanguage { return detected }
        guard let request = session.request else { return "" }
        return request.detectsSource
            ? "Detecting…"
            : Languages.name(for: request.sourceLanguage)
    }

    /// Picking a language here re-translates the same captured text, and
    /// becomes the default for the next time the shortcut fires.
    private var targetLanguage: Binding<String> {
        Binding(
            get: { session.request?.targetLanguage ?? Preferences.shared.targetLanguage },
            set: { code in
                guard var request = session.request, code != request.targetLanguage else { return }
                Preferences.shared.targetLanguage = code
                request.targetLanguage = code
                request.formality = Preferences.shared.effectiveFormality
                request.addresseeGender = Preferences.shared.effectiveAddresseeGender
                request.speakerGender = Preferences.shared.effectiveSpeakerGender
                session.start(request)
            }
        )
    }

    @ViewBuilder
    private func body(for session: TranslationSession) -> some View {
        ScrollView(.vertical) {
            Group {
                if let error = session.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                } else if session.output.isEmpty {
                    Text("Translating…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(session.output)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(HeightReporter())
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 44), maxBodyHeight))
        .onPreferenceChange(HeightPreference.self) { height in
            Task { @MainActor in contentHeight = height }
        }
    }

    private func copy() {
        Clipboard.write(session.trimmedOutput)
        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.easeOut(duration: 0.15)) { didCopy = false }
        }
    }
}

// MARK: - Buttons

/// A card action: a symbol, optionally with its name written out, on a fill
/// that appears on hover. Plain rather than `.accessoryBar`, whose disabled
/// state is too faint to tell from enabled on the HUD material — the same
/// reasoning as the inline language field.
private struct OverlayButton: View {
    var title: String?
    let symbol: String
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(title: String? = nil, symbol: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, title == nil ? 0 : 8)
            .frame(minWidth: 26, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering && isEnabled ? 0.12 : 0))
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
    }
}

// MARK: - Content measurement

/// The panel grows to fit the translation as it streams in, up to a cap past
/// which the body scrolls — so we need the text's natural height.
private struct HeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HeightReporter: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HeightPreference.self, value: proxy.size.height)
        }
    }
}
