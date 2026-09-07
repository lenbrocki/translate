import SwiftUI

/// The floating translation card. Deliberately small and quiet: it appears over
/// whatever the user is reading, so it borrows the system HUD material rather
/// than painting a window of its own.
struct OverlayView: View {
    @Bindable var session: TranslationSession
    var onClose: () -> Void
    /// The language list is a child window, so the panel resigns key while it
    /// is open. The host needs to know not to dismiss itself.
    var onPickerOpenChange: (Bool) -> Void = { _ in }

    @State private var contentHeight: CGFloat = 0
    @State private var didCopy = false

    private let width: CGFloat = 420
    private let maxBodyHeight: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            body(for: session)
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

            glyphButton(didCopy ? "checkmark" : "doc.on.doc", help: "Copy (⌘C)") {
                copy()
            }
            .disabled(session.trimmedOutput.isEmpty)

            glyphButton("xmark", help: "Close (⎋)", action: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: sourceLabel)
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

    private func glyphButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.accessoryBar)
        .help(help)
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
