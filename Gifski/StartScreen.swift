import SwiftUI

struct StartScreen: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				Image("GifInStillsSplash")
					.resizable()
					.interpolation(.high)
					.antialiased(true)
					.scaledToFill()
					.frame(width: proxy.size.width, height: proxy.size.height)
					.clipped()

				VStack {
					Spacer()

					VStack(spacing: 10) {
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
					.padding(.horizontal, 26)
					.padding(.vertical, 16)
					.background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
					.shadow(color: .black.opacity(0.10), radius: 20, y: 8)
					.padding(.bottom, 24)
				}
				.padding(.horizontal, 24)
			}
			.frame(width: proxy.size.width, height: proxy.size.height)
			.clipped()
		}
		.ignoresSafeArea()
		.navigationTitle("")
	}
}
