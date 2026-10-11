import SwiftUI

struct CalmModeButton: View {
    @ObservedObject var settings: CalmPlaybackSettings

    var body: some View {
        Button {
            settings.toggleCalmMode()
        } label: {
            Label(settings.state.isCalmEnabled ? "Turn Off Calm Mode" : "Turn On Calm Mode",
                  systemImage: settings.state.isCalmEnabled ? "leaf.fill" : "leaf")
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .help("Hold wallpaper motion; turning it off restores prior playback when other restrictions allow.")
    }
}
