import SwiftUI

enum CedarStyle {
    static let forest = Color(red: 0.13, green: 0.29, blue: 0.23)
    static let cream = Color(red: 0.97, green: 0.96, blue: 0.93)
}

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Label("cedar", systemImage: "leaf.fill")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .padding(.top, 24)

                    ZStack {
                        Circle().stroke(CedarStyle.forest.opacity(0.07), lineWidth: 1)
                            .frame(width: 240, height: 240)
                        Circle().stroke(CedarStyle.forest.opacity(0.12), lineWidth: 1)
                            .frame(width: 180, height: 180)
                        Circle().fill(CedarStyle.forest)
                            .frame(width: 116, height: 116)
                        Image(systemName: "waveform")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(CedarStyle.cream)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("A little space.\nA little clarity.")
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                            .accessibilityIdentifier("welcome.heading")
                        Text("Welcome to Cedar. A place for your thoughts, conversations, and the things you want to come back to.")
                            .font(.body)
                            .foregroundStyle(CedarStyle.forest.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    NavigationLink {
                        LibraryView()
                    } label: {
                        HStack {
                            Text("Get started")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .padding(20)
                        .foregroundStyle(CedarStyle.cream)
                        .background(CedarStyle.forest, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .accessibilityIdentifier("welcome.getStarted")
                    .padding(.top, 8)

                    Text("Your space, at your pace.")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(CedarStyle.forest)
            .background(CedarStyle.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(CedarStyle.forest)
        .preferredColorScheme(.light)
    }
}


#Preview {
    let store = RecordingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("CedarPreview"))
    WelcomeView()
        .environmentObject(store)
        .environmentObject(AudioController(store: store))
        .environmentObject(TranscriptionController(store: store))
}
