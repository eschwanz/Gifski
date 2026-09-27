import AVKit
import SwiftUI

struct ImageSequenceVideoConversionScreen: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(AppState.self) private var appState
	@State private var progress = 0.0

	let job: ImageSequenceJob

	var body: some View {
		VStack(spacing: 18) {
			ProgressView(value: progress)
				.progressViewStyle(.circular)
				.controlSize(.large)
			Text("Creating MP4")
				.font(.headline)
			Text(progress, format: .percent.precision(.fractionLength(0)))
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
		.fillFrame()
		.navigationTitle("Gif’in Stills")
		.task(priority: .utility) {
			do {
				try await convert()
			} catch {
				guard !error.isCancelled else {
					return
				}

				appState.error = error
				dismiss()
			}
		}
	}

	private func convert() async throws {
		let url = try await ImageSequenceVideoExporter.run(job) { progress in
			Task { @MainActor in
				self.progress = progress
			}
		}

		try Task.checkCancellation()
		try? url.setAppAsItemCreator()

		var path = appState.navigationPath
		path.removeLast()
		path.append(.sequenceVideoCompleted(url, sourceURL: job.sourceURL))
		appState.navigationPath = path
	}
}

struct SequenceVideoCompletedScreen: View {
	@Environment(AppState.self) private var appState
	@State private var isFileExporterPresented = false
	@State private var player: AVPlayer

	let url: URL
	let sourceURL: URL

	init(url: URL, sourceURL: URL) {
		self.url = url
		self.sourceURL = sourceURL
		self._player = .init(initialValue: AVPlayer(url: url))
	}

	var body: some View {
		VStack(spacing: 14) {
			VideoPlayer(player: player)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.clipShape(.rect(cornerRadius: 10))

			VStack(spacing: 3) {
				Text("Final MP4 size: \(url.fileSizeFormatted)")
					.font(.subheadline.weight(.medium))
				Text(url.filename)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(18)
		.safeAreaInset(edge: .bottom) {
			HStack {
				Button("New", systemImage: "plus") {
					appState.navigationPath = []
				}
				Spacer()
				ShareLink("Share", item: url)
				Button("Save MP4", systemImage: "square.and.arrow.down") {
					isFileExporterPresented = true
				}
				.buttonStyle(.borderedProminent)
			}
			.padding(.horizontal, 18)
			.padding(.vertical, 10)
			.background(.ultraThinMaterial)
		}
		.navigationTitle("Gif’in Stills")
		.fileExporter(
			isPresented: $isFileExporterPresented,
			item: ExportableMP4(url: url),
			defaultFilename: "\(sourceURL.filenameWithoutExtension).mp4"
		) { result in
			do {
				let savedURL = try result.get()
				try? savedURL.setAppAsItemCreator()
			} catch {
				appState.error = error
			}
		}
		.onAppear {
			player.play()
		}
		.onDisappear {
			player.pause()
		}
	}
}
