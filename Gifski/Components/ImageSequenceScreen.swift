import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageSequenceScreen: View {
	@Environment(AppState.self) private var appState
	@State private var job: ImageSequenceJob
	@State private var previewPosition = 0
	@State private var isPlaying = true
	@State private var isAddingImages = false
	@State private var isDropTargeted = false
	@State private var customWidth: Int
	@State private var customHeight: Int
	@State private var estimatedGIFBytes: Int?
	@State private var isEstimatingGIFSize = false

	init(job: ImageSequenceJob) {
		self._job = .init(initialValue: job)
		self._customWidth = .init(initialValue: job.outputWidth)
		self._customHeight = .init(initialValue: job.outputHeight)
	}

	var body: some View {
		VStack(spacing: 10) {
			preview
			settingsCard
			frameList
		}
		.padding(.horizontal, 16)
		.padding(.top, 10)
		.navigationTitle("Gif’in Stills")
		.navigationSubtitle("\(job.urls.count) images • \(job.duration.formatted(.number.precision(.fractionLength(2)))) s")
		.safeAreaInset(edge: .bottom) {
			bottomBar
				.padding(.horizontal, 16)
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
		.task(id: gifEstimateTaskID) {
			await updateGIFSizeEstimate()
		}
		.task(id: previewTaskID) {
			while !Task.isCancelled {
				let nanoseconds = UInt64((1_000_000_000 / Double(max(job.frameRate, 1))).rounded())
				try? await Task.sleep(nanoseconds: nanoseconds)

				guard isPlaying, !job.frameIndices.isEmpty else {
					continue
				}

				previewPosition = (previewPosition + 1) % job.frameIndices.count
			}
		}
		.onChange(of: job.socialVideoPreset) {
			applySocialPreset()
		}
		.onChange(of: job.outputFormat) {
			applyOutputFormat()
		}
	}

	private var gifEstimateTaskID: String {
		[
			job.outputFormat.rawValue,
			String(job.frameRate),
			String(job.quality),
			String(job.loop),
			String(job.bounce),
			String(job.outputWidth),
			String(job.outputHeight),
			job.urls.map(\.path).joined(separator: "|")
		].joined(separator: ":")
	}

	private var previewTaskID: String {
		"\(job.frameRate)-\(job.urls.count)-\(job.bounce)-\(isPlaying)"
	}

	private var previewSourceIndex: Int {
		let indices = job.frameIndices
		guard !indices.isEmpty else {
			return 0
		}
		return indices[previewPosition.clamped(to: 0...(indices.count - 1))]
	}

	private var preview: some View {
		ZStack(alignment: .bottomTrailing) {
			RoundedRectangle(cornerRadius: 10)
				.fill(.black.opacity(0.06))

			if
				job.urls.indices.contains(previewSourceIndex),
				let image = NSImage(contentsOf: job.urls[previewSourceIndex])
			{
				Image(nsImage: image)
					.resizable()
					.scaledToFit()
					.padding(8)
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

				Text("\(previewSourceIndex + 1) / \(job.urls.count)")
					.monospacedDigit()
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(8)
		}
		.frame(height: 180)
	}

	private var settingsCard: some View {
		VStack(alignment: .leading, spacing: 10) {
			ViewThatFits(in: .horizontal) {
				HStack(spacing: 14) {
					formatControl
					speedControl
					Toggle("Bounce", isOn: $job.bounce)
					if job.outputFormat == .gif {
						Toggle("Loop", isOn: $job.loop)
					}
					Spacer(minLength: 0)
					if job.outputFormat == .gif {
						qualityControl
					}
				}

				VStack(alignment: .leading, spacing: 8) {
					HStack(spacing: 14) {
						formatControl
						speedControl
						Toggle("Bounce", isOn: $job.bounce)
						if job.outputFormat == .gif {
							Toggle("Loop", isOn: $job.loop)
						}
					}
					if job.outputFormat == .gif {
						qualityControl
					}
				}
			}

			Divider()

			ViewThatFits(in: .horizontal) {
				HStack(spacing: 14) {
					dimensionsControl
					if job.outputFormat == .mp4 {
						socialPresetControl
					}
					Spacer(minLength: 0)
					outputSummary
				}

				VStack(alignment: .leading, spacing: 8) {
					dimensionsControl
					if job.outputFormat == .mp4 {
						socialPresetControl
					}
					outputSummary
				}
			}
		}
		.controlSize(.small)
		.padding(10)
		.background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
	}

	private var formatControl: some View {
		Picker("Format", selection: $job.outputFormat) {
			ForEach(ImageSequenceOutputFormat.allCases) {
				Text($0.rawValue).tag($0)
			}
		}
		.pickerStyle(.segmented)
		.frame(width: 145)
	}

	private var speedControl: some View {
		HStack(spacing: 6) {
			Text("Speed")
			Stepper(value: $job.frameRate, in: 3...50) {
				Text("\(job.frameRate) FPS")
					.monospacedDigit()
			}
		}
	}

	private var qualityControl: some View {
		HStack(spacing: 6) {
			Text("Quality")
			Slider(value: $job.quality, in: 0.1...1, step: 0.05)
				.frame(width: 100)
			Text(job.quality.formatted(.percent.precision(.fractionLength(0))))
				.monospacedDigit()
				.frame(width: 40, alignment: .trailing)
		}
	}

	private var dimensionsControl: some View {
		HStack(spacing: 6) {
			Text("Size")
			TextField("W", value: widthBinding, format: .number)
				.frame(width: 70)
				.multilineTextAlignment(.trailing)
			Text("×")
			TextField("H", value: heightBinding, format: .number)
				.frame(width: 70)
				.multilineTextAlignment(.trailing)
			Text("px")
				.foregroundStyle(.secondary)
		}
	}

	private var socialPresetControl: some View {
		Picker("Preset", selection: $job.socialVideoPreset) {
			ForEach(SocialVideoPreset.allCases) { preset in
				Text(preset == .custom ? preset.rawValue : "\(preset.rawValue) — \(preset.detail)")
					.tag(preset)
			}
		}
		.frame(maxWidth: 330)
	}

	private var outputSummary: some View {
		let dimensions = displayedOutputDimensions

		return HStack(spacing: 6) {
			Text("\(dimensions.width) × \(dimensions.height) • \(job.outputFormat == .mp4 ? "H.264" : "GIF")")

			if job.outputFormat == .gif, job.urls.count >= 2 {
				Text("•")

				if isEstimatingGIFSize {
					ProgressView()
						.controlSize(.mini)
					Text("Estimating size…")
				} else if let estimatedGIFBytes {
					Text("Estimated \(ByteCountFormatter.string(fromByteCount: Int64(estimatedGIFBytes), countStyle: .file))")
						.fontWeight(.medium)
				}
			}
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}

	private var widthBinding: Binding<Int> {
		.init(
			get: { job.outputWidth },
			set: {
				let value = max(2, $0)
				job.outputWidth = value
				customWidth = value
				job.socialVideoPreset = .custom
			}
		)
	}

	private var heightBinding: Binding<Int> {
		.init(
			get: { job.outputHeight },
			set: {
				let value = max(2, $0)
				job.outputHeight = value
				customHeight = value
				job.socialVideoPreset = .custom
			}
		)
	}

	private var displayedOutputDimensions: (width: Int, height: Int) {
		job.outputFormat == .mp4 ? job.effectiveMP4Dimensions : (job.outputWidth, job.outputHeight)
	}

	private var frameList: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("Frames")
					.font(.headline)
				Text("Drag rows to reorder")
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
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
								.frame(width: 42, height: 30)
								.clipped()
								.clipShape(.rect(cornerRadius: 4))
						}

						Text(url.lastPathComponent)
							.lineLimit(1)
						Spacer()
						Text("\(index + 1)")
							.font(.caption)
							.foregroundStyle(.tertiary)
							.monospacedDigit()
						Button(role: .destructive) {
							removeFrame(at: index)
						} label: {
							Image(systemName: "trash")
						}
						.buttonStyle(.borderless)
						.disabled(job.urls.count <= 2)
					}
				}
				.onMove(perform: moveFrames)
			}
			.frame(maxHeight: .infinity)
		}
	}

	private var bottomBar: some View {
		HStack(spacing: 12) {
			Button("Add Images", systemImage: "plus") {
				isAddingImages = true
			}

			Spacer()

			if job.urls.count < 2 {
				Label("Add at least one more image", systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				HStack(spacing: 6) {
					Text("\(job.urls.count) frames • \(job.duration.formatted(.number.precision(.fractionLength(2)))) s")

					if job.outputFormat == .gif {
						Text("•")

						if isEstimatingGIFSize {
							Text("Estimating…")
						} else if let estimatedGIFBytes {
							Text("~\(ByteCountFormatter.string(fromByteCount: Int64(estimatedGIFBytes), countStyle: .file))")
								.fontWeight(.medium)
						}
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			}

			Button(createButtonTitle, systemImage: "sparkles") {
				guard job.outputWidth >= 2, job.outputHeight >= 2 else {
					appState.error = ImageSequenceError.invalidDimensions
					return
				}

				var exportJob = job
				if exportJob.outputFormat == .mp4 {
					let dimensions = exportJob.effectiveMP4Dimensions
					exportJob.outputWidth = dimensions.width
					exportJob.outputHeight = dimensions.height
				}

				switch exportJob.outputFormat {
				case .gif:
					appState.navigationPath.append(.imageSequenceConversion(exportJob))
				case .mp4:
					appState.navigationPath.append(.imageSequenceVideoConversion(exportJob))
				}
			}
			.buttonStyle(.borderedProminent)
			.disabled(job.urls.count < 2)
			.keyboardShortcut(.return, modifiers: [.command])
		}
	}

	private var createButtonTitle: String {
		job.outputFormat == .gif ? "Create GIF" : "Create MP4"
	}

	private func updateGIFSizeEstimate() async {
		guard job.outputFormat == .gif, job.urls.count >= 2 else {
			estimatedGIFBytes = nil
			isEstimatingGIFSize = false
			return
		}

		isEstimatingGIFSize = true
		estimatedGIFBytes = nil

		do {
			try await Task.sleep(for: .milliseconds(450))
			try Task.checkCancellation()

			let estimateJob = job
			let data = try await ImageSequenceGenerator.run(estimateJob) { _ in }
			try Task.checkCancellation()

			estimatedGIFBytes = data.count
			isEstimatingGIFSize = false
		} catch {
			guard !error.isCancelled else {
				return
			}

			estimatedGIFBytes = nil
			isEstimatingGIFSize = false
		}
	}

	private func applySocialPreset() {
		guard job.outputFormat == .mp4 else {
			return
		}

		guard let dimensions = job.socialVideoPreset.dimensions else {
			job.outputWidth = customWidth
			job.outputHeight = customHeight
			return
		}

		job.outputWidth = dimensions.width
		job.outputHeight = dimensions.height
	}

	private func applyOutputFormat() {
		previewPosition = 0
		if job.outputFormat == .gif {
			job.outputWidth = customWidth
			job.outputHeight = customHeight
		} else {
			applySocialPreset()
		}
	}

	private func addImages(_ urls: [URL]) {
		let sortedCandidates = urls
			.filter(ImageSequenceLoader.isImage)
			.sorted {
				$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
			}

		var seen = Set(job.urls.map(\.standardizedFileURL))
		var additions = [URL]()
		for url in sortedCandidates {
			let key = url.standardizedFileURL
			guard seen.insert(key).inserted else {
				continue
			}
			appState.beginImageSequenceSecurityScopedAccess(url)
			additions.append(url)
		}

		guard !additions.isEmpty else {
			return
		}

		job.urls.append(contentsOf: additions)
		previewPosition = min(previewPosition, max(0, job.frameIndices.count - 1))
	}

	private func moveFrames(from offsets: IndexSet, to destination: Int) {
		job.urls.move(fromOffsets: offsets, toOffset: destination)
		previewPosition = 0
	}

	private func removeFrame(at index: Int) {
		guard job.urls.count > 2, job.urls.indices.contains(index) else {
			return
		}

		let removedURL = job.urls.remove(at: index)
		appState.endImageSequenceSecurityScopedAccess(removedURL)
		previewPosition = 0
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

		let url = try data.writeToUniqueTemporaryFile(filename: job.displayName, contentType: .gif)
		try? url.setAppAsItemCreator()

		var path = appState.navigationPath
		path.removeLast()
		path.append(.completed(data, url, sourceURL: job.sourceURL))
		appState.navigationPath = path
	}
}
