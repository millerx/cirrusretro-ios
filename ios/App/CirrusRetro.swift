import SwiftUI
import UniformTypeIdentifiers

@main
struct CirrusRetroApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        WindowGroup { PlayerView(model: model) }
    }
}

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @State private var choosing = false
    @State private var query = ""
    @State private var pendingRemoval: Recording?
    @State private var tab = 0

    private var visibleRecordings: [Recording] {
        model.recordings.filter { $0.matches(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                List {
                    if model.importing { ProgressView("Importing…") }
                    if let message = model.libraryMessage { Text(message) }
                    if model.recordings.isEmpty && !model.busy {
                        Text("Import NSF, SPC or VGM files to start your library.")
                            .foregroundStyle(.secondary)
                    } else if visibleRecordings.isEmpty && !query.isEmpty {
                        Text("No matching recordings").foregroundStyle(.secondary)
                    }
                    ForEach(visibleRecordings) { item in
                        NavigationLink {
                            RecordingView(model: model, id: item.id) { tab = 1 }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(subtitle(item))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Remove", role: .destructive) { pendingRemoval = item }
                                .disabled(model.busy)
                        }
                    }
                }
                .navigationTitle("Library")
                .searchable(text: $query, prompt: "Search music")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { choosing = true } label: { Label("Import from Files", systemImage: "plus") }
                            .disabled(model.busy)
                    }
                }
                .fileImporter(isPresented: $choosing, allowedContentTypes: [.data],
                              allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): model.open(urls)
                    case .failure(let error):
                        if (error as NSError).code != NSUserCancelledError {
                            model.libraryMessage = error.localizedDescription
                        }
                    }
                }
                .confirmationDialog("Remove from Library?", isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ), presenting: pendingRemoval) { item in
                    Button("Remove", role: .destructive) { model.remove(item) }
                } message: { item in
                    Text(item.title)
                }
            }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(0)

            NavigationStack { NowPlayingView(model: model) }
                .tabItem { Label("Playback", systemImage: "play.circle") }
                .badge(model.player.upcoming.count)
                .tag(1)
        }
    }

    private func subtitle(_ item: Recording) -> String {
        if !item.available { return "File missing" }
        return [item.metadata.artist, item.metadata.format.rawValue]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct RecordingView: View {
    @ObservedObject var model: PlayerModel
    let id: Recording.ID
    let showPlayback: () -> Void

    var body: some View {
        if let item = model.recordings.first(where: { $0.id == id }) {
            let metadata = item.metadata
            List {
                Section("Recording") {
                    LabeledContent("File", value: item.fileName)
                    LabeledContent("Format", value: metadata.format.rawValue)
                    if !metadata.artist.isEmpty { LabeledContent("Artist", value: metadata.artist) }
                    if !metadata.copyright.isEmpty { LabeledContent("Copyright", value: metadata.copyright) }
                }
                if let message = model.player.message { Text(message) }
                if item.available {
                    Section("Tracks") {
                        ForEach(0..<metadata.trackCount, id: \.self) { track in
                            let isPlaying = model.player.isPlaying(recordingID: item.id, track: track)
                            HStack {
                                Button {
                                    model.play(item, track: track)
                                    showPlayback()
                                } label: {
                                    Label("Track \(track + 1)", systemImage: isPlaying ? "speaker.wave.2" : "play")
                                        .frame(minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(isPlaying ? "Show playback for track \(track + 1)" : "Play track \(track + 1)")
                                .accessibilityValue(isPlaying ? "Playing" : "")
                                Spacer()
                                Button {
                                    model.enqueue(item, track: track)
                                } label: {
                                    Image(systemName: "text.badge.plus")
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add track \(track + 1) to queue")
                            }
                        }
                    }
                    .disabled(model.busy)
                } else {
                    Text("File missing. Import it again to restore playback.")
                }
            }
            .navigationTitle(item.title)
        } else {
            Text("Recording unavailable")
        }
    }
}

private struct NowPlayingView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        let snapshot = model.player
        let playback = snapshot.playback
        List {
            if let recording = snapshot.recording {
                Section("Now Playing") {
                    Text(recording.title)
                    Picker("Track", selection: Binding(get: { playback.track }, set: model.select)) {
                        ForEach(0..<playback.count, id: \.self) { track in
                            Text("\(track + 1) of \(playback.count)").tag(track)
                        }
                    }
                    LabeledContent("Status", value: playback.transport.rawValue)
                    if playback.transport == .playing {
                        Button("Pause", action: model.pause)
                    } else {
                        Button("Play", action: model.play)
                    }
                    Button("Stop", action: model.stop).disabled(playback.transport == .stopped)
                }
            }
            if let message = snapshot.message { Text(message) }
            Section("Up Next") {
                if snapshot.upcoming.isEmpty {
                    Text("Queue is empty").foregroundStyle(.secondary)
                } else {
                    Button("Play Next", action: model.next).disabled(model.busy)
                    ForEach(snapshot.upcoming) { item in
                        VStack(alignment: .leading) {
                            Text(item.recording.title)
                            Text("Track \(item.track + 1)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { model.dequeue(item.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Playback")
    }
}
