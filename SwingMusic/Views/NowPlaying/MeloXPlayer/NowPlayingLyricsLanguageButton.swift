import SwiftUI

struct NowPlayingLyricsLanguageButton: View {
    @Environment(AppSettings.self) private var settings

    let hasTranslations: Bool
    let hasRomanizations: Bool

    var body: some View {
        @Bindable var settings = settings

        Menu {
            if hasRomanizations {
                Toggle(
                    "Show pronunciation",
                    isOn: $settings.lyricsRomanizationEnabled
                )

                Picker(
                    "Romanization scope",
                    selection:
                        $settings.lyricsRomanizationDisplayMode
                ) {
                    ForEach(
                        LyricsTranslationDisplayMode.allCases
                    ) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
            }

            if hasTranslations {
                Toggle(
                    "Show translation",
                    isOn: $settings.lyricsTranslationEnabled
                )

                Picker(
                    "Translation scope",
                    selection:
                        $settings.lyricsTranslationDisplayMode
                ) {
                    ForEach(
                        LyricsTranslationDisplayMode.allCases
                    ) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
            }
        } label: {
            Image(systemName: "translate")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    .white.opacity(
                        hasEnabledAnnotation
                            ? 0.18
                            : 0.1
                    ),
                    in: .circle
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Translation and pronunciation")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Choose whether to show romanization and translation")
    }

    private var hasEnabledAnnotation: Bool {
        (hasRomanizations && settings.lyricsRomanizationEnabled)
            || (hasTranslations && settings.lyricsTranslationEnabled)
    }

    private var accessibilityValue: String {
        var enabledAnnotations: [String] = []
        if hasRomanizations && settings.lyricsRomanizationEnabled {
            enabledAnnotations.append("Romanization")
        }
        if hasTranslations && settings.lyricsTranslationEnabled {
            enabledAnnotations.append("Translation")
        }
        guard !enabledAnnotations.isEmpty else {
            return "Annotations hidden"
        }
        let scopes: [String] = [
            hasRomanizations && settings.lyricsRomanizationEnabled
                ? "Romanization\(settings.lyricsRomanizationDisplayMode.title)"
                : nil,
            hasTranslations && settings.lyricsTranslationEnabled
                ? "Translation\(settings.lyricsTranslationDisplayMode.title)"
                : nil,
        ].compactMap { $0 }
        return scopes.joined(separator: "，")
    }
}
