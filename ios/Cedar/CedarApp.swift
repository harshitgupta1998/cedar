import SwiftUI

@main
struct CedarApp: App {
    @StateObject private var store: RecordingStore
    @StateObject private var audio: AudioController

    init() {
        let store = RecordingStore()
        _store = StateObject(wrappedValue: store)
        _audio = StateObject(wrappedValue: AudioController(store: store))
    }

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .environmentObject(store)
                .environmentObject(audio)
        }
    }
}
