import SwiftUI

struct SleepTimerSheet: View {
    @ObservedObject var timer = SleepTimer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMinutes = 15

    private let options = [5, 10, 15, 20, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            List {
                if timer.active {
                    Section {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundStyle(.blue)
                            Text("Time remaining")
                            Spacer()
                            Text(timer.displayTime)
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)
                        }

                        Toggle(isOn: $timer.fadeOut) {
                            HStack {
                                Image(systemName: "speaker.wave.1")
                                    .foregroundStyle(.secondary)
                                Text("Fade out")
                            }
                        }

                        Button(role: .destructive) {
                            timer.cancel()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel Timer")
                            }
                        }
                    }
                } else {
                    Section {
                        Picker(selection: $selectedMinutes) {
                            ForEach(options, id: \.self) { mins in
                                Text(mins < 60 ? "\(mins) min" : "\(mins / 60) h\(mins > 60 ? " \(mins % 60) min" : "")").tag(mins)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.blue)
                                Text("Duration")
                                    .foregroundStyle(.blue)
                            }
                        }

                        Button {
                            timer.start(minutes: selectedMinutes)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Start Timer")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                            }
                        }
                    }

                    Section {
                        Button {
                            let remaining = max(1, Int((AudioPlayer.shared.total - AudioPlayer.shared.time) / 60) + 1)
                            timer.start(minutes: remaining)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.blue)
                                Text("End of current song")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }

                    Section {
                        Toggle(isOn: $timer.fadeOut) {
                            HStack {
                                Image(systemName: "speaker.wave.1")
                                    .foregroundStyle(.secondary)
                                Text("Fade out before stopping")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
