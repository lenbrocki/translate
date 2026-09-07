import SwiftUI

struct MainView: View {
    @Bindable private var preferences = Preferences.shared
    @State private var session = TranslationSession()
    @State private var input = ""
    @State private var didCopy = false
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
        .onAppear { AppCore.shared.registerWindowOpener { openWindow(id: WindowID.main) } }
    }

    // MARK: - Controls

    /// Sits directly on the window surface, in the title bar's row. There is no
    /// bar of its own: the window chrome is the background.
    private var controlBar: some View {
        HStack(spacing: 10) {
            LanguageField(selection: $preferences.sourceLanguage, includesAutoDetect: true, width: 168)

            Button(action: swapLanguages) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Swap languages")
            .disabled(preferences.sourceLanguage == Languages.autoDetect)

            LanguageField(selection: $preferences.targetLanguage, width: 168)

            Spacer(minLength: 16)

            Picker("Register", selection: registerSelection) {
                ForEach(Formality.allCases) { formality in
                    Text(formality.label).tag(formality)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
    ///
    /// The pill lines up with the segmented control by itself; its label does
    /// not — AppKit centres a segment's text optically, discounting the
    /// descender space, while a SwiftUI button centres the text's full frame,
    /// which leaves it sitting two points low next to its neighbour. Hence the
    /// offset, measured off a screenshot.
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
            .offset(y: -2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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

            Picker(title, selection: selection) {
                ForEach(Gender.allCases) { gender in
                    Text(gender.label).tag(gender)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
                } else {
                    Button("Translate") { translate() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
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
                if let detected = session.detectedLanguage {
                    Text(detected)
                        .transition(.opacity)
                }

                Spacer()

                Button(didCopy ? "Copied" : "Copy") { copy() }
                    .controlSize(.regular)
                    .disabled(session.trimmedOutput.isEmpty)
            }
        }
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.35), value: session.detectedLanguage)
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

    /// Shows Auto, and refuses to move off it, for a target language with no
    /// formal or familiar distinction, without overwriting the saved choice.
    private var registerSelection: Binding<Formality> {
        Binding(
            get: { preferences.effectiveFormality },
            set: { if marksFormality { preferences.formality = $0 } }
        )
    }

    /// Same treatment for the two genders: pinned to Auto where the language
    /// never inflects for them, and the saved choice survives.
    private var addresseeGenderSelection: Binding<Gender> {
        Binding(
            get: { preferences.effectiveAddresseeGender },
            set: { if marksAddresseeGender { preferences.addresseeGender = $0 } }
        )
    }

    private var speakerGenderSelection: Binding<Gender> {
        Binding(
            get: { preferences.effectiveSpeakerGender },
            set: { if marksSpeakerGender { preferences.speakerGender = $0 } }
        )
    }

    // MARK: - Actions

    private func translate() {
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

    private func copy() {
        Clipboard.write(session.trimmedOutput)
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3)) { didCopy = false }
        }
    }

    private func swapLanguages() {
        guard preferences.sourceLanguage != Languages.autoDetect else { return }
        let previousSource = preferences.sourceLanguage
        preferences.sourceLanguage = preferences.targetLanguage
        preferences.targetLanguage = previousSource
        if !session.output.isEmpty {
            let translated = session.trimmedOutput
            session.reset()
            input = translated
        }
    }
}
