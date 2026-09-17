import SwiftUI

struct MainView: View {
    @Bindable private var preferences = Preferences.shared
    @State private var session = TranslationSession()
    @State private var input = ""
    @State private var didCopy = false
    /// The translation waiting for typing to pause.
    @State private var autoTranslate: Task<Void, Never>?
    /// The selection in another app this window's text was captured from, when
    /// it arrived from the overlay. Replace pastes the translation back there.
    @State private var replacementTarget: ReplacementTarget?
    /// Gender is the exception rather than the rule, so the row starts folded
    /// away; a dot on the button says when a choice is in force.
    @State private var showsGender = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    /// One radius scale for the window: the well, and controls at the
    /// concentric step inside it.
    private let wellRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if showsGender { genderRow }
            well
        }
        .frame(minWidth: 880, minHeight: 460)
        .onAppear {
            AppCore.shared.registerWindowOpener { openWindow(id: WindowID.main) }
            takeHandoff()
        }
        .onReceive(NotificationCenter.default.publisher(for: .translationHandoff)) { _ in
            takeHandoff()
        }
        .onChange(of: input) { old, new in scheduleTranslation(from: old, to: new) }
    }

    // MARK: - Controls

    /// Sits directly on the window surface, in the title bar's row. There is no
    /// bar of its own: the window chrome is the background.
    private var controlBar: some View {
        HStack(spacing: 10) {
            LanguageField(
                selection: $preferences.sourceLanguage,
                includesAutoDetect: true,
                detectedLanguage: session.detectedLanguage,
                width: 168
            )

            Button(action: swapLanguages) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .hoverHighlight(opacity: 0.09)
            .help(swapSource == nil
                  ? "Swap languages — available once the source language is known"
                  : "Swap languages")
            .disabled(swapSource == nil)

            LanguageField(selection: $preferences.targetLanguage, width: 168)

            Spacer(minLength: 16)

            SegmentedPicker(selection: registerSelection, options: Formality.allCases) { $0.label }
                .disabled(!marksFormality)
                .help(marksFormality
                      ? "Level of address to use in the translation"
                      : "\(targetName) makes no formal or informal distinction")
                .frame(width: 186)

            genderButton
        }
        // Clears the window controls, which float over the content.
        .padding(.leading, 82)
        .padding(.trailing, 20)
        .frame(height: 52)
    }

    /// Folds the two gender pickers away. Collapsed it still has to say
    /// whether it is doing anything, or a setting made once would go on
    /// changing translations invisibly — hence the dot.
    private var genderButton: some View {
        Button {
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)) {
                showsGender.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Text("Gender")
                if genderIsSet {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(showsGender ? 0 : -90))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .hoverHighlight()
        .disabled(!marksAnyGender)
        .help(genderHelp)
    }

    /// Two pickers rather than one: a message is as often from a woman to a
    /// man as the other way round, and Polish marks both ends of that.
    private var genderRow: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            genderPicker(
                "Speaker",
                selection: speakerGenderSelection,
                enabled: marksSpeakerGender,
                help: marksSpeakerGender
                    ? "Gender of whoever is speaking — the \"I\" of the text, which \(targetName) inflects for"
                    : "\(targetName) does not change with the speaker's gender"
            )

            genderPicker(
                "Addressee",
                selection: addresseeGenderSelection,
                enabled: marksAddresseeGender,
                help: marksAddresseeGender
                    ? "Gender of the person the text addresses, which \(targetName) inflects for"
                    : "\(targetName) does not change with the addressee's gender"
            )
        }
        .padding(.leading, 82)
        .padding(.trailing, 20)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func genderPicker(
        _ title: String,
        selection: Binding<Gender>,
        enabled: Bool,
        help: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(enabled ? .secondary : .tertiary)

            SegmentedPicker(selection: selection, options: Gender.allCases) { $0.label }
                .disabled(!enabled)
                .frame(width: 172)
        }
        .help(help)
    }

    // MARK: - The well

    /// Both texts live in one recessed surface rather than two panes butted
    /// against the window edge, so the window reads as chrome around content.
    private var well: some View {
        HStack(spacing: 0) {
            inputHalf
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            outputHalf
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: wellRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: wellRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.07), radius: 10, y: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var inputHalf: some View {
        PlainTextEditor(
            text: $input,
            placeholder: "Type or paste text to translate…",
            focusOnAppear: true
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            halfFooter {
                if !input.isEmpty {
                    Text("\(input.count) characters")
                        .monospacedDigit()
                }

                Spacer()

                if session.isStreaming {
                    Button("Stop") { session.cancel() }
                        .keyboardShortcut(".", modifiers: .command)
                        .controlSize(.regular)
                        .hoverHighlight()
                } else {
                    Button("Translate") { translate() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .hoverHighlight(tint: .white, opacity: 0.14)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var outputHalf: some View {
        ZStack(alignment: .top) {
            if let error = session.errorMessage {
                errorState(error)
            } else {
                PlainTextEditor(
                    text: .constant(session.output),
                    placeholder: "Translation appears here.",
                    isEditable: false
                )
                .transition(.opacity)
            }

            // The stream is its own progress indicator once text starts
            // arriving; this covers the wait before the first token.
            ProgressView()
                .progressViewStyle(.linear)
                .controlSize(.small)
                .frame(height: 2)
                .opacity(session.isStreaming && session.output.isEmpty ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: session.isStreaming)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            halfFooter {
                Spacer()

                if let target = replacementTarget, !target.app.isTerminated {
                    Button("Replace in \(target.app.localizedName ?? "App")") { replace(in: target) }
                        .controlSize(.regular)
                        .hoverHighlight()
                        .disabled(session.isStreaming || session.trimmedOutput.isEmpty || session.errorMessage != nil)
                        .help("Paste the translation over the text selected there")
                }

                Button(didCopy ? "Copied" : "Copy") { copy() }
                    .controlSize(.regular)
                    .hoverHighlight()
                    .disabled(session.trimmedOutput.isEmpty)
            }
        }
    }

    /// Same surface as the well, so text scrolls out of sight behind it
    /// instead of colliding with the buttons.
    private func halfFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(height: 44)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func errorState(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .regular))
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Register and gender

    private var targetName: String {
        Languages.name(for: preferences.targetLanguage)
    }

    private var marksFormality: Bool {
        Languages.marksFormality(preferences.targetLanguage)
    }

    private var marksAddresseeGender: Bool {
        Languages.marksAddresseeGender(preferences.targetLanguage)
    }

    private var marksSpeakerGender: Bool {
        Languages.marksSpeakerGender(preferences.targetLanguage)
    }

    private var marksAnyGender: Bool { marksAddresseeGender || marksSpeakerGender }

    /// Whether either picker is doing something, judged on what will actually
    /// be sent — a saved Female for a language that ignores gender is not.
    private var genderIsSet: Bool {
        preferences.effectiveSpeakerGender != .auto || preferences.effectiveAddresseeGender != .auto
    }

    private var genderHelp: String {
        guard marksAnyGender else {
            return "\(targetName) does not change with anyone's gender"
        }
        guard genderIsSet else {
            return "Gender of the speaker and of the person addressed, which \(targetName) inflects for"
        }
        return "Speaker: \(preferences.effectiveSpeakerGender.label) · Addressee: \(preferences.effectiveAddresseeGender.label)"
    }

    // Register and gender only change how the text is phrased, so a new choice
    // re-translates straight away rather than waiting for ⌘↩. That happens in
    // these setters, not on a preference change: a language swap also moves
    // the effective values, and that should not start a translation.

    /// Shows Auto, and refuses to move off it, for a target language with no
    /// formal or familiar distinction, without overwriting the saved choice.
    private var registerSelection: Binding<Formality> {
        Binding(
            get: { preferences.effectiveFormality },
            set: {
                guard marksFormality, $0 != preferences.formality else { return }
                preferences.formality = $0
                translate()
            }
        )
    }

    /// Same treatment for the two genders: pinned to Auto where the language
    /// never inflects for them, and the saved choice survives.
    private var addresseeGenderSelection: Binding<Gender> {
        Binding(
            get: { preferences.effectiveAddresseeGender },
            set: {
                guard marksAddresseeGender, $0 != preferences.addresseeGender else { return }
                preferences.addresseeGender = $0
                translate()
            }
        )
    }

    private var speakerGenderSelection: Binding<Gender> {
        Binding(
            get: { preferences.effectiveSpeakerGender },
            set: {
                guard marksSpeakerGender, $0 != preferences.speakerGender else { return }
                preferences.speakerGender = $0
                translate()
            }
        )
    }

    // MARK: - Actions

    /// How long typing has to pause before the text is sent. Every request
    /// costs a model call, so this errs long: a pause between words (a few
    /// hundred milliseconds) must not fire, a pause at the end of a phrase
    /// should.
    private let typingPause: Duration = .milliseconds(1000)

    /// Translates as the text changes. A paste — more than one character
    /// arriving in a single edit — goes straight out, since there is nothing
    /// more to wait for; typing waits for `typingPause`.
    private func scheduleTranslation(from old: String, to new: String) {
        autoTranslate?.cancel()
        let text = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            session.reset()
            return
        }
        // Whitespace-only edits, and the text a handoff just brought in along
        // with its translation, have nothing new to translate.
        guard text != session.request?.text else { return }

        let isPaste = new.count - old.count > 1
        autoTranslate = Task {
            if !isPaste {
                try? await Task.sleep(for: typingPause)
                guard !Task.isCancelled else { return }
            }
            translate()
        }
    }

    private func translate() {
        autoTranslate?.cancel()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.start(
            TranslationRequest(
                text: text,
                sourceLanguage: preferences.sourceLanguage,
                targetLanguage: preferences.targetLanguage,
                formality: preferences.effectiveFormality,
                addresseeGender: preferences.effectiveAddresseeGender,
                speakerGender: preferences.effectiveSpeakerGender,
                effort: preferences.effort,
                provider: preferences.provider
            )
        )
    }

    /// Picks up a translation sent over from the overlay, replacing whatever
    /// the window was showing.
    private func takeHandoff() {
        guard let handoff = AppCore.shared.takeHandoff() else { return }
        input = handoff.snapshot.request.text
        session.restore(handoff.snapshot)
        replacementTarget = handoff.target
    }

    /// One replace per selection: once pasted over, the text it was captured
    /// from is gone, so the button goes with it.
    private func replace(in target: ReplacementTarget) {
        let translation = session.trimmedOutput
        guard !translation.isEmpty else { return }
        replacementTarget = nil
        Task { await target.paste(translation) }
    }

    private func copy() {
        Clipboard.write(session.trimmedOutput)
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3)) { didCopy = false }
        }
    }

    /// The source side as a concrete language: the pinned one, or the one
    /// detection settled on. Swapping needs it, because "Detect language"
    /// cannot become a target.
    private var swapSource: String? {
        guard preferences.sourceLanguage == Languages.autoDetect else { return preferences.sourceLanguage }
        return session.detectedLanguage.flatMap(Languages.code(forDetectedName:))
    }

    private func swapLanguages() {
        guard let previousSource = swapSource else { return }
        preferences.sourceLanguage = preferences.targetLanguage
        preferences.targetLanguage = previousSource
        if !session.output.isEmpty {
            let translated = session.trimmedOutput
            session.reset()
            input = translated
            // The window now holds the translation as its source text, so it
            // no longer answers the selection it was captured from.
            replacementTarget = nil
            // Straight back the other way, without waiting out the typing
            // pause the input change would otherwise schedule.
            translate()
        }
    }
}
