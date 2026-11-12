import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageSequenceOutputFormat: String, CaseIterable, Identifiable, Hashable {
	case gif = "GIF"
	case mp4 = "MP4"

	var id: Self { self }
}

enum SocialVideoPreset: String, CaseIterable, Identifiable, Hashable {
	case custom = "Custom"
	case instagramSquare = "Instagram Square"
	case instagramPortrait = "Instagram Portrait"
	case reelsStoriesTikTok = "Reels / Stories / TikTok"
	case youtubeLandscape = "YouTube / LinkedIn Landscape"

	var id: Self { self }

	var dimensions: (width: Int, height: Int)? {
		switch self {
		case .custom:
			nil
		case .instagramSquare:
			(1080, 1080)
		case .instagramPortrait:
			(1080, 1350)
		case .reelsStoriesTikTok:
			(1080, 1920)
		case .youtubeLandscape:
			(1920, 1080)
		}
	}

	var detail: String {
		switch self {
		case .custom:
			"Use custom dimensions."
		case .instagramSquare:
			"1:1 • 1080 × 1080"
		case .instagramPortrait:
			"4:5 • 1080 × 1350"
		case .reelsStoriesTikTok:
			"9:16 • 1080 × 1920"
		case .youtubeLandscape:
			"16:9 • 1920 × 1080"
		}
	}
}

struct ImageSequenceJob: Hashable {
	var urls: [URL]
	var frameRate: Double
	var quality: Double
	var loop: Bool
	var bounce: Bool
	var outputWidth: Int
	var outputHeight: Int
	var outputFormat: ImageSequenceOutputFormat
	var socialVideoPreset: SocialVideoPreset

	init(
		urls: [URL],
		frameRate: Double = 10,
		quality: Double = 1,
		loop: Bool = true,
		bounce: Bool = false,
		outputWidth: Int,
		outputHeight: Int,
		outputFormat: ImageSequenceOutputFormat = .gif,
		socialVideoPreset: SocialVideoPreset = .custom
	) {
		self.urls = urls
		self.frameRate = frameRate
		self.quality = quality
		self.loop = loop
		self.bounce = bounce
		self.outputWidth = outputWidth
		self.outputHeight = outputHeight
		self.outputFormat = outputFormat
		self.socialVideoPreset = socialVideoPreset
	}

	var sourceURL: URL {
		urls[0]
	}

	var displayName: String {
		"\(sourceURL.filenameWithoutExtension)-animation"
	}

	var frameIndices: [Int] {
		let forward = Array(urls.indices)
		guard bounce, urls.count > 1 else {
			return forward
		}
		return forward + Array((0..<(urls.count - 1)).reversed())
	}

	var duration: Double {
		Double(frameIndices.count) / max(frameRate, 0.1)
	}

	var effectiveMP4Dimensions: (width: Int, height: Int) {
		(
			max(2, outputWidth - (outputWidth % 2)),
			max(2, outputHeight - (outputHeight % 2))
		)
	}
}

enum ImageSequenceError: LocalizedError {
	case notEnoughImages
	case mixedInput
	case unreadableImage(URL)
	case invalidDimensions

	var errorDescription: String? {
		switch self {
		case .notEnoughImages:
			"Select at least two still images."
		case .mixedInput:
			"Select either one video or a group of still images, not a mixture of both."
		case .unreadableImage(let url):
			"Could not read \(url.lastPathComponent)."
		case .invalidDimensions:
			"The output dimensions must be at least 2 × 2 pixels."
		}
	}
}

enum ImageSequenceLoader {
	static func isImage(_ url: URL) -> Bool {
		url.contentType?.conforms(to: .image) == true
	}

	/**
	Loads an image with its EXIF/HEIC orientation applied.
	*/
	static func loadCGImage(_ url: URL) throws -> CGImage {
		guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
			throw ImageSequenceError.unreadableImage(url)
		}

		let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
		let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 1
		let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 1
		let maximumPixelSize = max(pixelWidth, pixelHeight)

		let options = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
			kCGImageSourceShouldCacheImmediately: true,
			kCGImageSourceShouldAllowFloat: true
		] as CFDictionary

		guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
			throw ImageSequenceError.unreadableImage(url)
		}

		return image
	}

	/**
	Fits the source image into the output canvas without stretching it. Empty canvas areas remain transparent;
	the MP4 exporter composites that result over white because H.264 does not support alpha.
	*/
	static func normalizedImage(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
		guard width >= 2, height >= 2 else {
			throw ImageSequenceError.invalidDimensions
		}

		guard let context = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			throw ImageSequenceError.invalidDimensions
		}

		context.clear(CGRect(x: 0, y: 0, width: width, height: height))
		context.interpolationQuality = .high

		let scale = min(
			Double(width) / Double(image.width),
			Double(height) / Double(image.height)
		)
		let drawWidth = Double(image.width) * scale
		let drawHeight = Double(image.height) * scale
		let drawRect = CGRect(
			x: (Double(width) - drawWidth) / 2,
			y: (Double(height) - drawHeight) / 2,
			width: drawWidth,
			height: drawHeight
		)
		context.draw(image, in: drawRect)

		guard let result = context.makeImage() else {
			throw ImageSequenceError.invalidDimensions
		}

		return result
	}
}

actor ImageSequenceGenerator {
	static func run(
		_ job: ImageSequenceJob,
		onProgress: @escaping @Sendable (Double) -> Void
	) async throws -> Data {
		guard job.urls.count >= 2 else {
			throw ImageSequenceError.notEnoughImages
		}

		guard job.outputWidth >= 2, job.outputHeight >= 2 else {
			throw ImageSequenceError.invalidDimensions
		}

		let loop: Gifski.Loop = job.loop ? .forever : .never
		let gifski = try Gifski(
			dimensions: (job.outputWidth, job.outputHeight),
			quality: job.quality.clamped(to: 0.1...1),
			loop: loop
		)

		let frameRate = job.frameRate.clamped(to: Constants.allowedImageSequenceFrameRate)
		let frameDuration = 1 / frameRate
		let orderedIndices = job.frameIndices

		for (outputIndex, sourceIndex) in orderedIndices.enumerated() {
			try Task.checkCancellation()
			let sourceImage = try ImageSequenceLoader.loadCGImage(job.urls[sourceIndex])
			let image = try ImageSequenceLoader.normalizedImage(
				sourceImage,
				width: job.outputWidth,
				height: job.outputHeight
			)

			try gifski.addFrame(
				image,
				frameNumber: outputIndex,
				presentationTimestamp: Double(outputIndex) * frameDuration
			)

			onProgress(Double(outputIndex + 1) / Double(orderedIndices.count))
		}

		try Task.checkCancellation()
		return try gifski.finish()
	}
}

extension AppState {
	func start(_ urls: [URL]) {
		guard !urls.isEmpty else {
			return
		}

		if urls.count == 1, let url = urls.first, !ImageSequenceLoader.isImage(url) {
			start(url)
			return
		}

		guard urls.allSatisfy(ImageSequenceLoader.isImage) else {
			error = ImageSequenceError.mixedInput
			return
		}

		let sortedURLs = urls.sorted {
			$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
		}

		releaseImageSequenceSecurityScopedAccess()
		for url in sortedURLs {
			beginImageSequenceSecurityScopedAccess(url)
		}

		do {
			let firstImage = try ImageSequenceLoader.loadCGImage(sortedURLs[0])
			let job = ImageSequenceJob(
				urls: sortedURLs,
				frameRate: Double(Defaults[.outputFPS]),
				quality: Defaults[.outputQuality],
				loop: Defaults[.loopGIF],
				bounce: Defaults[.bounceGIF],
				outputWidth: firstImage.width,
				outputHeight: firstImage.height
			)

			mode = .normal
			navigationPath = [.imageSequence(job)]
		} catch {
			self.error = error
		}
	}

	func start(_ itemProviders: [NSItemProvider]) {
		guard !isOpeningVideo else {
			return
		}

		isOpeningVideo = true

		Task { [self] in
			var urls = [URL]()

			for itemProvider in itemProviders {
				if let url = await itemProvider.getURL() {
					urls.append(url)
				}
			}

			isOpeningVideo = false
			start(urls)
		}
	}
}
