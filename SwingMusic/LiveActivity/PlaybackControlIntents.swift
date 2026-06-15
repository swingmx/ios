import AppIntents
import Foundation

enum WidgetPlaybackCommand: String {
    case toggle
    case next
    case previous
}

enum WidgetPlaybackBridge {
    static let suite = "group.swingmusic"
    static let commandKey = "widget.command"
    static let timestampKey = "widget.commandAt"
    static let notification = "group.swingmusic.playback.command"

    static func send(_ command: WidgetPlaybackCommand) {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.set(command.rawValue, forKey: commandKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
        defaults.synchronize()

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notification as CFString),
            nil,
            nil,
            true
        )
    }
}

struct TogglePlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle Playback"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetPlaybackBridge.send(.toggle)
        return .result()
    }
}

struct NextTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetPlaybackBridge.send(.next)
        return .result()
    }
}

struct PreviousTrackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        WidgetPlaybackBridge.send(.previous)
        return .result()
    }
}
