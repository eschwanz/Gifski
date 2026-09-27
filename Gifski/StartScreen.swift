import SwiftUI

struct StartScreen: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				Image("GifInStillsSplash")
					.resizable()
					.scaledToFill()
					.frame(width: proxy.size.width, height: proxy.size.height)
					.clipped()

				VStack {
					Spacer()

					VStack(spacing: 9) {
						if appState.isOpeningVideo {
							ProgressView("Opening…")
						} else {
							Text("Drop images or a video")
								.font(.headline)
							Text("Turn stills into a GIF or social-ready MP4.")
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
					.padding(.vertical, 14)
					.background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
					.padding(.bottom, 22)
				}
				.padding(.horizontal, 24)
			}
		}
		.navigationTitle("")
	}
}
