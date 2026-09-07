import Combine
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings()
                .tabItem { Label("Shortcut", systemImage: "command") }
            AccountSettings()
                .tabItem { Label("API Keys", systemImage: "key") }
        }
        .frame(width: 480)
    }
}

struct GeneralSettings: View {
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                Picker("Translate with", selection: $preferences.provider) {
                    ForEach(Provider.allCases) { provider in
                        Text(provider.modelLabel).tag(provider)
                    }
                }
            } footer: {
                Text(providerFooter)
                    .font(.caption)
                    .foregroundStyle(preferences.hasAPIKey ? Color.secondary : Color.red)
            }

            Section {
                Picker("Quality", selection: $preferences.effort) {
                    ForEach(Effort.allCases) { effort in
                        Text(effort.label).tag(effort)
                    }
                }
            } footer: {
                Text("How much deliberation \(preferences.provider.modelLabel) spends on the wording. Higher is slower and costs more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Register", selection: $preferences.formality) {
                    ForEach(Formality.allCases) { formality in
                        Text(formality.label).tag(formality)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Formal uses the polite level of address where the language has one: Pan/Pani in Polish, Sie in German, vous in French.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Speaker", selection: $preferences.speakerGender) {
                    ForEach(Gender.allCases) { gender in
                        Text(gender.label).tag(gender)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Addressee", selection: $preferences.addresseeGender) {
                    ForEach(Gender.allCases) { gender in
                        Text(gender.label).tag(gender)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Gender")
            } footer: {
                Text("Who is speaking — the \"I\" of the text — and who is being addressed, for languages that inflect for them: zrobiłem/zrobiłam and Pan/Pani in Polish, masculine and feminine verb forms in Hebrew and Arabic. Both start folded away in the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Copy the translation when it finishes", isOn: $preferences.autoCopy)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private var providerFooter: String {
        preferences.hasAPIKey
            ? "Both providers get the same instructions, so the register and gender settings mean the same thing either way."
            : "No \(preferences.provider.vendor) API key saved yet — add one under API Keys."
    }
}

struct ShortcutSettings: View {
    @Bindable private var preferences = Preferences.shared
    @State private var error = ""
    @State private var isTrusted = SelectionCapture.hasAccessibilityPermission

    private let permissionPoll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Translate selection") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(combo: $preferences.shortcut) { error = $0 }
                        Button("Reset") { reset() }
                            .disabled(preferences.shortcut == .default)
                    }
                }
                if !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Translates whatever text is selected in any app into a floating card, without leaving the app you're in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 10) {
                        Label(
                            isTrusted ? "Granted" : "Not granted",
                            systemImage: isTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(isTrusted ? .green : .orange)
                        .labelStyle(.titleAndIcon)

                        if !isTrusted {
                            Button("Grant…") { SelectionCapture.requestAccessibilityPermission() }
                        }
                    }
                }
            } footer: {
                Text("macOS requires this so the shortcut can read the selection out of other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onReceive(permissionPoll) { _ in
            isTrusted = SelectionCapture.hasAccessibilityPermission
        }
    }

    private func reset() {
        do {
            try AppCore.shared.setShortcut(.default)
            preferences.shortcut = .default
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AccountSettings: View {
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        Form {
            ForEach(Provider.allCases) { provider in
                Section {
                    ProviderKeyRow(provider: provider)
                } header: {
                    HStack(spacing: 6) {
                        Text(provider.vendor)
                        if preferences.provider == provider {
                            Text("in use")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                    }
                } footer: {
                    if provider == Provider.allCases.last {
                        Text("Stored in your login keychain, one key per provider. This is the only place Translate reads them from — the ANTHROPIC_API_KEY and OPENAI_API_KEY in your shell environment are deliberately ignored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

/// One provider's key: paste, save, see what's stored, remove it.
private struct ProviderKeyRow: View {
    let provider: Provider

    @Bindable private var preferences = Preferences.shared
    @State private var draft = ""
    @State private var saved = false

    var body: some View {
        LabeledContent("API key") {
            HStack(spacing: 8) {
                // Prompt rather than a title: a `SecureField`'s title becomes
                // a visible label of its own inside a Form, printed next to the
                // box instead of in it.
                SecureField(text: $draft, prompt: Text(provider.keyPlaceholder)) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(minWidth: 200)
                    .onSubmit(save)
                Button(saved ? "Saved" : "Save") { save() }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }

        LabeledContent("Status") {
            Text(status)
                .foregroundStyle(preferences.hasAPIKey(for: provider) ? Color.secondary : Color.red)
                .font(.callout)
        }

        if preferences.hasAPIKey(for: provider) {
            Button("Remove saved key", role: .destructive) {
                preferences.clearAPIKey(for: provider)
            }
        }
    }

    private var status: String {
        preferences.hasAPIKey(for: provider)
            ? "Using the key in your keychain (\(preferences.apiKeyHint(for: provider)))."
            : "No key configured. \(provider.modelLabel) won't work until you add one."
    }

    private func save() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        preferences.setAPIKey(draft, for: provider)
        draft = ""
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            saved = false
        }
    }
}
