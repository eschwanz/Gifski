import SwiftUI

struct StartScreen: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		ZStack {
			Image("GifInStillsSplash")
				.resizable()
				.scaledToFill()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.clipped()

			VStack {
				Spacer()

				VStack(spacing: 10) {
					if appState.isOpeningVideo {
						ProgressView("Opening…")
					} else {
						Text("Drop images or a video")
							.font(.headline)
						Text("Multiple stills become an animated GIF.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Button("Choose Files…", systemImage: "plus") {
							appState.isFileImporterPresented = true
						}
						.buttonStyle(.borderedProminent)
						.controlSize(.large)
					}
				}
				.padding(.horizontal, 24)
				.padding(.vertical, 16)
				.background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
				.padding(.bottom, 24)
			}
			.padding(.horizontal, 24)
		}
		.navigationTitle("")
	}
}
