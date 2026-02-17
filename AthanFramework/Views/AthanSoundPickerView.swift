import SwiftUI
import AVFoundation

/// Dedicated picker for athan reciter selection with preview playback.
struct AthanSoundPickerView: View {
    let selected: AthanSound
    let onSelect: (AthanSound) -> Void

    @State private var currentSelection: AthanSound
    @State private var player: AVAudioPlayer?
    @State private var playingSound: AthanSound?

    init(selected: AthanSound, onSelect: @escaping (AthanSound) -> Void) {
        self.selected = selected
        self.onSelect = onSelect
        self._currentSelection = State(initialValue: selected)
    }

    var body: some View {
        List {
            ForEach(AthanSound.allCases) { sound in
                HStack(spacing: 12) {
                    // Selection checkmark
                    Image(systemName: currentSelection == sound ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(currentSelection == sound ? AthanTheme.accent : AthanTheme.textSecondary.opacity(0.5))
                        .font(.system(size: 20))

                    // Sound name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sound.displayName)
                            .foregroundStyle(AthanTheme.textPrimary)
                        if sound == .defaultTone {
                            Text("System alarm tone")
                                .font(.caption)
                                .foregroundStyle(AthanTheme.textSecondary)
                        }
                    }

                    Spacer()

                    // Play/stop button
                    if sound.fileName != nil {
                        Button {
                            togglePlayback(sound)
                        } label: {
                            Image(systemName: playingSound == sound ? "stop.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AthanTheme.accent)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    currentSelection = sound
                    onSelect(sound)
                }
                .listRowBackground(Color.white.opacity(currentSelection == sound ? 0.05 : 0))
            }
        }
        .navigationTitle("Athan Reciter")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player?.stop()
            player = nil
        }
    }

    private func togglePlayback(_ sound: AthanSound) {
        // If this sound is already playing, stop it
        if playingSound == sound {
            player?.stop()
            player = nil
            playingSound = nil
            return
        }

        // Stop any current playback
        player?.stop()
        player = nil
        playingSound = nil

        guard let fileName = sound.fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.delegate = AudioPlayerDelegate.shared
            AudioPlayerDelegate.shared.onFinish = { [weak audioPlayer] in
                if self.player === audioPlayer {
                    self.playingSound = nil
                    self.player = nil
                }
            }
            audioPlayer.play()
            player = audioPlayer
            playingSound = sound
        } catch {
            print("[AthanSoundPicker] Playback failed: \(error)")
        }
    }
}

/// Delegate to detect when playback finishes naturally.
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    static let shared = AudioPlayerDelegate()
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            onFinish?()
        }
    }
}
