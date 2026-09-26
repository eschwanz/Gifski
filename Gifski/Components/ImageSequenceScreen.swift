import AppKit
import SwiftUI

struct ImageSequenceScreen: View {
	@Environment(AppState.self) private var appState
	@State private var job: ImageSequenceJob
	@State private var previewIndex = 0
	@State private var isPlaying = true
	@State private var isAddingImages = false

	init(job: ImageSequenceJob) {
		self._job = .init(initialValue: job)
	}

	var body: some View {
		VStack(spacing: 16) {
			preview
			settings
			frameList
			bottomBar
		}
		.padding(20)
		.navigationTitle(job.displayName)
		.fileImporter(
			isPresented: $isAddingImages,
			allowedContentTypes: [.image],
			allowsMultipleSelection: true
		) { result in
			do {
				let urls = try result.get()
				guard !urls.isEmpty else {
					return
				}

				for url in urls {
					_ = url.startAccessingSecurityScopedResource()
				}

				job.urls.append(contentsOf: urls)
				job.urls = Array(Set(job.urls)).sorted {
					$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
				}
				previewIndex = min(previewIndex, max(0, job.urls.count - 1))
			} catch {
				appState.error = error
			}
		}
		.task(id: previewTaskID) {
			while !Task.isCancelled {
				let nanoseconds = UInt64((1_000_000_000 / Double(max(job.frameRate, 1))).rounded())
				try? await Task.sleep(nanoseconds: nanoseconds)

				guard isPlaying, !job.urls.isEmpty else {
					continue
				}

				previewIndex = (previewIndex + 1) % job.urls.count
			}
		}
	}

	private var previewTaskID: String {
		"\(job.frameRate)-\(job.urls.count)-\(isPlaying)"
	}

	private var preview: some View {
		VStack(spacing: 8) {
			ZStack {
				Rectangle()
					.fill(.black.opacity(0.08))

				if
					!job.urls.isEmpty,
					let image = NSImage(contentsOf: job.urls[previewIndex])
				{
					Image(nsImage: image)
						.resizable()
						.scaledToFit()
						.padding(12)
				} else {
					ContentUnavailableView("No Preview", systemImage: "photo.on.rectangle.angled")
				}
			}
			.frame(height: 250)
			.clipShape(.rect(cornerRadius: 10))

			HStack {
				Button {
					isPlaying.toggle()
				} label: {
					Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
				}

				Spacer()

				Text("\(previewIndex + 1) / \(job.urls.count)")
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		}
	}

	private var settings: some View {
		Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
			GridRow {
				Text("Frame rate")
				.gridColumnAlignment(.trailing)
				.foregroundStyle(.secondary)
				.frame(width: 90, alignment: .trailing)

				HStack {
					Stepper(value: $job.frameRate, in: 3...50) {
						Text("\(job.frameRate) FPS")
							.monospacedDigit()
					}
				}
			}

			GridRow {
				Text("Quality")
					.foregroundStyle(.secondary)

				HStack {
					Slider(value: $job.quality, in: 0.1...1, step: 0.05)
					Text(job.quality.formatted(.percent.precision(.fractionLength(0))))
						.monospacedDigit()
						.frame(width: 48, alignment: .trailing)
				}
			}

			GridRow {
				Text("Size")
					.foregroundStyle(.secondary)

				HStack {
					TextField("Width", value: $job.outputWidth, format: .number)
						.frame(width: 82)
					Text("×")
						.foregroundStyle(.secondary)
					TextField("Height", value: $job.outputHeight, format: .number)
						.frame(width: 82)
					Text("px")
						.foregroundStyle(.secondary)
				}
			}

			GridRow {
				Text("Playback")
					.foregroundStyle(.secondary)

				HStack(spacing: 18) {
					Toggle("Loop", isOn: $job.loop)
					Toggle("Bounce", isOn: $job.bounce)
				}
			}
		}
		.textFieldStyle(.roundedBorder)
	}

	private var frameList: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Frames")
					.font(.headline)
				Text("\(job.urls.count)")
					.foregroundStyle(.secondary)
				Spacer()
				Button("Add Images…", systemImage: "plus") {
					isAddingImages = true
				}
			}

			List {
				ForEach(Array(job.urls.enumerated()), id: \.element) { index, url in
					HStack(spacing: 10) {
						if let image = NSImage(contentsOf: url) {
							Image(nsImage: image)
								.resizable()
								.scaledToFill()
								.frame(width: 52, height: 40)
								.clipped()
								.clipShape(.rect(cornerRadius: 4))
						}

						Text(url.lastPathComponent)
							.lineLimit(1)
						Spacer()
						Text("#\(index + 1)")
							.monospacedDigit()
							.foregroundStyle(.secondary)

						Button {
							moveFrame(at: index, by: -1)
						} label: {
							Image(systemName: "chevron.up")
						}
						.disabled(index == 0)

						Button {
							moveFrame(at: index, by: 1)
						} label: {
							Image(systemName: "chevron.down")
						}
						.disabled(index == job.urls.count - 1)

						Button(role: .destructive) {
							removeFrame(at: index)
						} label: {
							Image(systemName: "trash")
						}
						.disabled(job.urls.count <= 2)
					}
				}
			}
			.frame(height: 180)
		}
	}

	private var bottomBar: some View {
		HStack {
			Text(sequenceDuration, format: .number.precision(.fractionLength(2)))
				.monospacedDigit()
				.foregroundStyle(.secondary)
			Text("seconds")
				.foregroundStyle(.secondary)

			Spacer()

			Button("Convert to GIF", systemImage: "sparkles") {
				guard job.outputWidth > 0, job.outputHeight > 0 else {
					appState.error = ImageSequenceError.invalidDimensions
					return
				}

				appState.navigationPath.append(.imageSequenceConversion(job))
			}
			.buttonStyle(.borderedProminent)
			.keyboardShortcut(.return, modifiers: [.command])
		}
	}

	private var sequenceDuration: Double {
		let frameCount = job.bounce ? (job.urls.count * 2 - 1) : job.urls.count
		return Double(frameCount) / Double(max(job.frameRate, 1))
	}

	private func moveFrame(at index: Int, by offset: Int) {
		let newIndex = index + offset
		guard job.urls.indices.contains(index), job.urls.indices.contains(newIndex) else {
			return
		}

		job.urls.swapAt(index, newIndex)
		previewIndex = newIndex
	}

	private func removeFrame(at index: Int) {
		guard job.urls.count > 2, job.urls.indices.contains(index) else {
			return
		}

		job.urls.remove(at: index)
		previewIndex = min(previewIndex, job.urls.count - 1)
	}
}

struct ImageSequenceConversionScreen: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(AppState.self) private var appState
	@State private var progress = 0.0

	let job: ImageSequenceJob

	var body: some View {
		VStack(spacing: 18) {
			ProgressView(value: progress)
				.progressViewStyle(.circular)
				.controlSize(.large)
			Text("Converting Image Sequence")
				.font(.headline)
			Text(progress, format: .percent.precision(.fractionLength(0)))
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
		.fillFrame()
		.navigationTitle("")
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
		let data = try await ImageSequenceGenerator.run(job) { progress in
			Task { @MainActor in
				self.progress = progress
			}
		}

		try Task.checkCancellation()

		let filename = job.displayName
		let url = try data.writeToUniqueTemporaryFile(filename: filename, contentType: .gif)
		try? url.setAppAsItemCreator()

		var path = appState.navigationPath
		path.removeLast()
		path.append(.completed(data, url, sourceURL: job.sourceURL))
		appState.navigationPath = path
	}
}
