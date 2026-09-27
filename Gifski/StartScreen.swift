import AppKit
import SwiftUI

struct StartScreen: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		GeometryReader { proxy in
			ZStack {
				if let image = SplashImageData.image {
					Image(nsImage: image)
						.resizable()
						.scaledToFill()
						.frame(width: proxy.size.width, height: proxy.size.height)
						.clipped()
				} else {
					Color(red: 0.98, green: 0.96, blue: 0.90)
				}

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
					.shadow(color: .black.opacity(0.08), radius: 20, y: 8)
					.padding(.bottom, 22)
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
