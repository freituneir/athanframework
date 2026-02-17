import SwiftUI

/// Lets the user pick an Athan sound for their alarm.
struct SoundPickerView: View {
    @Binding var selectedSound: String
    @State private var playingSound: String?

    var body: some View {
        List {
            ForEach(SoundManager.availableSounds, id: \.fileName) { sound in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSound = sound.fileName
                    }
                    // TODO: Preview sound playback via AVAudioPlayer
                    playingSound = sound.fileName
                    // Reset playing indicator after a brief moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if playingSound == sound.fileName {
                            playingSound = nil
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Sound icon with play state
                        Image(systemName: playingSound == sound.fileName ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .font(.body)
                            .foregroundStyle(selectedSound == sound.fileName ? AthanTheme.accent : .secondary)
                            .symbolEffect(.variableColor, isActive: playingSound == sound.fileName)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sound.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if let description = sound.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if selectedSound == sound.fileName {
                            Image(systemName: "checkmark")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(AthanTheme.accent)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(
                    selectedSound == sound.fileName
                        ? AthanTheme.accent.opacity(0.08)
                        : nil
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(sound.displayName)\(sound.description.map { ", \($0)" } ?? "")")
                .accessibilityValue(selectedSound == sound.fileName ? "Selected" : "")
                .accessibilityHint("Double tap to select this sound")
                .accessibilityAddTraits(selectedSound == sound.fileName ? .isSelected : [])
            }
        }
        .navigationTitle("Alarm Sound")
        .sensoryFeedback(.selection, trigger: selectedSound)
    }
}
