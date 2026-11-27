import SwiftUI
import UniformTypeIdentifiers

@main
struct CirrusRetroApp: App {
    @StateObject private var model = PlayerModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup { PlayerView(model: model) }
            .onChange(of: phase) { phase in
                if phase == .background { model.pause() }
            }
    }
}

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @State private var choosing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { choosing = true } label: {
                        Label("Import NSF, SPC or VGM from Files", systemImage: "folder")
                    }.disabled(model.importing)
                    if model.importing { ProgressView("Importing…") }
                }
                if model.state.count > 0 {
                    Section("Recording") {
                        LabeledContent("Title", value: model.state.title.isEmpty ? "Untitled" : model.state.title)
                        if !model.state.artist.isEmpty { LabeledContent("Artist", value: model.state.artist) }
                        if !model.state.copyright.isEmpty { LabeledContent("Copyright", value: model.state.copyright) }
                    }
                    Section("Playback") {
                        Picker("Track", selection: Binding(get: { model.state.track }, set: model.select)) {
                            ForEach(0..<model.state.count, id: \.self) { track in
                                Text("\(track + 1) of \(model.state.count)").tag(track)
                            }
                        }
                        LabeledContent("Status", value: model.state.transport.rawValue)
                        if model.state.transport == .playing {
                            Button("Pause", action: model.pause)
                        } else {
                            Button("Play", action: model.play)
                        }
                        Button("Stop", action: model.stop).disabled(model.state.transport == .stopped)
                    }
                }
                if let message = model.message { Section("Error") { Text(message) } }
            }
            .navigationTitle("Cirrus Retro")
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url): model.open(url)
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { model.message = error.localizedDescription }
                }
            }
        }
    }
}
