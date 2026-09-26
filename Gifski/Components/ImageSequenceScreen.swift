import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageSequenceScreen: View {
	@Environment(AppState.self) private var appState
	@State private var job: ImageSequenceJob
	@State private var previewIndex = 0
	@State private var isPlaying = true
	@State private var isAddingImages = false
	@State private var isDropTargeted = false

	init(job: ImageSequenceJob) {
		self._job = .init(initialValue: job)
	}

	var body: some View {
		VStack(spacing: 12) {
			preview
			compactSettings
			frameList
		}
		.padding(.horizontal, 18)
		.padding(.top, 12)
		.navigationTitle("Gif’in Stills")
		.navigationSubtitle("\(job.urls.count) frames • \(sequenceDuration.formatted(.number.precision(.fractionLength(2)))) s")
		.safeAreaInset(edge: .bottom) {
			bottomBar
				.padding(.horizontal, 18)
				.padding(.vertical, 10)
				.background(.ultraThinMaterial)
		}
		.fileImporter(
			isPresented: $isAddingImages,
			allowedContentTypes: [.image],
			allowsMultipleSelection: true
		) { result in
			do {
				addImages(try result.get())
			} catch {
				appState.error = error
			}
		}
		.border(isDropTargeted ? Color.accentColor : .clear, width: 4, cornerRadius: 10)
		.onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
			Task {
				var urls = [URL]()
				for provider in providers {
					if let url = await provider.getURL(), ImageSequenceLoader.isImage(url) {
						urls.append(url)
					}
				}
				await MainActor.run {
					addImages(urls)
				}
			}
			return true
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
		ZStack(alignment: .bottomTrailing) {
			RoundedRectangle(cornerRadius: 10)
				.fill(.black.opacity(0.06))

			if
				!job.urls.isEmpty,
				let image = NSImage(contentsOf: job.urls[previewIndex])
			{
				Image(nsImage: image)
					.resizable()
					.scaledToFit()
					.padding(10)
			} else {
				ContentUnavailableView("Drop Images Here", systemImage: "photo.on.rectangle.angled")
			}

			HStack(spacing: 8) {
				Button {
					isPlaying.toggle()
				} label: {
					Image(systemName: isPlaying ? "pause.fill" : "play.fill")
				}
				.buttonStyle(.glass)

				Text("\(previewIndex + 1) / \(job.urls.count)")
					.monospacedDigit()
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(10)
		}
		.frame(height: 205)
	}

	private var compactSettings: some View {
		HStack(spacing: 18) {
			LabeledContent("Speed") {
				Stepper(value: $job.frameRate, in: 3...50) {
					Text("\(job.frameRate) FPS")
						.monospacedDigit()
				}
			}

			Divider()
				.frame(height: 28)

			LabeledContent("Quality") {
				HStack(spacing: 8) {
					Slider(value: $job.quality, in: 0.1...1, step: 0.05)
						.frame(width: 110)
					Text(job.quality.formatted(.percent.precision(.fractionLength(0))))
						.monospacedDigit()
						.frame(width: 42, alignment: .trailing)
				}
			}

			Divider()
				.frame(height: 28)

			Toggle("Loop", isOn: $job.loop)
			Toggle("Bounce", isOn: $job.bounce)
		}
		.controlSize(.small)
		.padding(.horizontal, 4)
	}

	private var frameList: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("Frames")
					.font(.headline)
				Spacer()
				Text("\(job.outputWidth) × \(job.outputHeight) px")
					.font(.caption)
					.foregroundStyle(.secondary)
				Button("Add", systemImage: "plus") {
					isAddingImages = true
				}
			}

			List {
				ForEach(Array(job.urls.enumerated()), id: \.element) { index, url in
					HStack(spacing: 8) {
						if let image = NSImage(contentsOf: url) {
							Image(nsImage: image)
								.resizable()
								.scaledToFill()
								.frame(width: 44, height: 32)
								.clipped()
								.clipShape(.rect(cornerRadius: 4))
						}

						Text(url.lastPathComponent)
							.lineLimit(1)
						Spacer()

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
			.frame(maxHeight: .infinity)
		}
	}

	private var bottomBar: some View {
		HStack {
			Button("Add Images", systemImage: "plus") {
				isAddingImages = true
			}

			Spacer()

			Text("\(job.urls.count) frames • \(sequenceDuration.formatted(.number.precision(.fractionLength(2)))) s")
				.font(.caption)
				.foregroundStyle(.secondary)

			Button("Create GIF", systemImage: "sparkles") {
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

	private func addImages(_ urls: [URL]) {
		let imageURLs = urls.filter(ImageSequenceLoader.isImage)
		guard !imageURLs.isEmpty else {
			return
		}

		for url in imageURLs {
			_ = url.startAccessingSecurityScopedResource()
		}

		job.urls.append(contentsOf: imageURLs)
		job.urls = Array(Set(job.urls)).sorted {
			$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
		}
		previewIndex = min(previewIndex, max(0, job.urls.count - 1))
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
			Text("Creating GIF")
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
