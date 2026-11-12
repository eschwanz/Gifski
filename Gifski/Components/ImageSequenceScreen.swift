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
		VStack(spacing: 12) {
			previewSection
			settingsCard
			frameList
		}
		.padding(.horizontal, 16)
		.padding(.top, 12)
		.navigationTitle("Gif’in Stills")
		.navigationSubtitle(exportSummaryLine)
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
		.border(isDropTargeted ? Color.accentColor : .clear, width: 4, cornerRadius: 12)
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
				let nanoseconds = UInt64((1_000_000_000 / max(job.frameRate, 0.1)).rounded())
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

	// MARK: Preview

	private var previewSection: some View {
		GeometryReader { proxy in
			let container = CGSize(
				width: max(1, proxy.size.width - 36),
				height: max(1, proxy.size.height - 36)
			)
			let target = CGSize(
				width: CGFloat(max(displayedOutputDimensions.width, 1)),
				height: CGFloat(max(displayedOutputDimensions.height, 1))
			)
			let canvasSize = fittedSize(container: container, aspect: target)

			ZStack {
				RoundedRectangle(cornerRadius: 14)
					.fill(.black.opacity(0.055))

				HStack {
					Spacer(minLength: 18)

					ZStack {
						Rectangle()
							.fill(job.outputFormat == .mp4 ? Color.white : Color.clear)

						previewImageView
							.padding(8)
					}
					.frame(width: canvasSize.width, height: canvasSize.height)
					.background(.white.opacity(job.outputFormat == .mp4 ? 1 : 0.45))
					.clipShape(.rect(cornerRadius: 10))
					.overlay {
						RoundedRectangle(cornerRadius: 10)
							.stroke(.black.opacity(0.10), lineWidth: 1)
					}
					.shadow(color: .black.opacity(0.08), radius: 8, y: 3)

					Spacer(minLength: 18)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

				VStack {
					HStack {
						Label(
							"\(displayedOutputDimensions.width) × \(displayedOutputDimensions.height)",
							systemImage: "rectangle.aspectratio"
						)
						.font(.caption.weight(.medium))
						.padding(.horizontal, 10)
						.padding(.vertical, 6)
						.background(.ultraThinMaterial, in: Capsule())

						Spacer()

						Text("\(previewSourceIndex + 1) / \(job.urls.count)")
							.font(.caption.weight(.medium))
							.monospacedDigit()
							.padding(.horizontal, 10)
							.padding(.vertical, 6)
							.background(.ultraThinMaterial, in: Capsule())
					}

					Spacer()

					HStack {
						Text(previewOverlaySubtitle)
							.font(.caption)
							.foregroundStyle(.secondary)
							.padding(.horizontal, 10)
							.padding(.vertical, 6)
							.background(.ultraThinMaterial, in: Capsule())

						Spacer()

						Button {
							isPlaying.toggle()
						} label: {
							Image(systemName: isPlaying ? "pause.fill" : "play.fill")
								.font(.system(size: 13, weight: .semibold))
								.frame(width: 34, height: 34)
						}
						.buttonStyle(.plain)
						.background(.ultraThinMaterial, in: Circle())
					}
				}
				.padding(12)
			}
		}
		.frame(minHeight: 220, idealHeight: 260, maxHeight: 300)
	}

	@ViewBuilder
	private var previewImageView: some View {
		if
			job.urls.indices.contains(previewSourceIndex),
			let image = NSImage(contentsOf: job.urls[previewSourceIndex])
		{
			Image(nsImage: image)
				.resizable()
				.interpolation(.high)
				.antialiased(true)
				.scaledToFit()
		} else {
			ContentUnavailableView("Drop Images Here", systemImage: "photo.on.rectangle.angled")
		}
	}

	// MARK: Settings

	private var settingsCard: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Text("Export")
					.font(.headline)
				Spacer()
				outputSummary
			}

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
				}

				VStack(alignment: .leading, spacing: 8) {
					dimensionsControl

					if job.outputFormat == .mp4 {
						socialPresetControl
					}
				}
			}
		}
		.controlSize(.small)
		.padding(12)
		.background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
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
			Stepper(
				value: $job.frameRate,
				in: Constants.allowedImageSequenceFrameRate,
				step: 0.1
			) {
				Text("\(frameRateText) FPS")
					.monospacedDigit()
					.frame(minWidth: 58, alignment: .trailing)
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
				.frame(width: 76)
				.multilineTextAlignment(.trailing)
			Text("×")
			TextField("H", value: heightBinding, format: .number)
				.frame(width: 76)
				.multilineTextAlignment(.trailing)
			Text("px")
				.foregroundStyle(.secondary)
		}
	}

	private var socialPresetControl: some View {
		HStack(spacing: 6) {
			Text("Preset")
			Picker("Preset", selection: $job.socialVideoPreset) {
				ForEach(SocialVideoPreset.allCases) { preset in
					Text(preset == .custom ? preset.rawValue : "\(preset.rawValue) — \(preset.detail)")
						.tag(preset)
				}
			}
			.labelsHidden()
			.frame(maxWidth: 360)
		}
	}

	private var outputSummary: some View {
		HStack(spacing: 6) {
			if job.outputFormat == .gif, job.urls.count >= 2 {
				if isEstimatingGIFSize {
					ProgressView()
						.controlSize(.mini)
					Text("Estimating size…")
				} else if let estimatedGIFBytes {
					Text("Estimated \(ByteCountFormatter.string(fromByteCount: Int64(estimatedGIFBytes), countStyle: .file))")
						.fontWeight(.medium)
				}
			} else if job.outputFormat == .mp4 {
				Text("H.264")
			}
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}

	// MARK: Frames

	private var frameList: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Frames")
					.font(.headline)

				Text("Drag rows to reorder")
					.font(.caption)
					.foregroundStyle(.secondary)

				Spacer()

				Button("Add Images", systemImage: "plus") {
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
								.frame(width: 44, height: 36)
								.clipped()
								.clipShape(.rect(cornerRadius: 5))
						}

						VStack(alignment: .leading, spacing: 2) {
							Text(url.lastPathComponent)
								.lineLimit(1)

							Text("Frame \(index + 1)")
								.font(.caption2)
								.foregroundStyle(.secondary)
						}

						Spacer()

						Button(role: .destructive) {
							removeFrame(at: index)
						} label: {
							Image(systemName: "trash")
						}
						.buttonStyle(.borderless)
						.disabled(job.urls.count <= 2)
					}
					.padding(.vertical, 2)
				}
				.onMove(perform: moveFrames)
			}
			.frame(maxHeight: .infinity)
		}
	}

	// MARK: Bottom bar

	private var bottomBar: some View {
		HStack(spacing: 12) {
			if job.urls.count < 2 {
				Label("Add at least one more image", systemImage: "exclamationmark.triangle")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				Text(exportSummaryLine)
					.font(.caption)
					.foregroundStyle(.secondary)

				if job.outputFormat == .gif {
					Text("•")
						.foregroundStyle(.secondary)

					if isEstimatingGIFSize {
						Text("Estimating…")
							.font(.caption)
							.foregroundStyle(.secondary)
					} else if let estimatedGIFBytes {
						Text("~\(ByteCountFormatter.string(fromByteCount: Int64(estimatedGIFBytes), countStyle: .file))")
							.font(.caption.weight(.medium))
							.foregroundStyle(.secondary)
					}
				}
			}

			Spacer()

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

	// MARK: Computed values

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

	private var displayedOutputDimensions: (width: Int, height: Int) {
		job.outputFormat == .mp4
			? job.effectiveMP4Dimensions
			: (job.outputWidth, job.outputHeight)
	}

	private var createButtonTitle: String {
		job.outputFormat == .gif ? "Create GIF" : "Create MP4"
	}

	private var frameRateText: String {
		job.frameRate.formatted(.number.precision(.fractionLength(1)))
	}

	private var previewOverlaySubtitle: String {
		"\(job.outputFormat.rawValue) · \(frameRateText) FPS · \(job.duration.formatted(.number.precision(.fractionLength(2)))) s"
	}

	private var exportSummaryLine: String {
		let dimensions = displayedOutputDimensions
		var summary = "\(job.outputFormat.rawValue) · \(dimensions.width) × \(dimensions.height) · \(frameRateText) FPS · \(job.urls.count) frames · \(job.duration.formatted(.number.precision(.fractionLength(2)))) s"

		if job.outputFormat == .mp4 {
			summary += " · H.264"
		}

		return summary
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

	// MARK: Actions

	private func fittedSize(container: CGSize, aspect: CGSize) -> CGSize {
		guard aspect.width > 0, aspect.height > 0 else {
			return CGSize(width: 200, height: 200)
		}

		let scale = min(container.width / aspect.width, container.height / aspect.height)

		return CGSize(
			width: max(1, aspect.width * scale),
			height: max(1, aspect.height * scale)
		)
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
