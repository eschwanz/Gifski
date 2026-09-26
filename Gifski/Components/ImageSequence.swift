import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageSequenceJob: Hashable {
	var urls: [URL]
	var frameRate: Int
	var quality: Double
	var loop: Bool
	var bounce: Bool
	var outputWidth: Int
	var outputHeight: Int

	init(
		urls: [URL],
		frameRate: Int = 10,
		quality: Double = 1,
		loop: Bool = true,
		bounce: Bool = false,
		outputWidth: Int,
		outputHeight: Int
	) {
		self.urls = urls
		self.frameRate = frameRate
		self.quality = quality
		self.loop = loop
		self.bounce = bounce
		self.outputWidth = outputWidth
		self.outputHeight = outputHeight
	}

	var sourceURL: URL {
		urls[0]
	}

	var displayName: String {
		let folderName = sourceURL.deletingLastPathComponent().lastPathComponent
		return folderName.isEmpty ? "Image Sequence" : folderName
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
			"The output dimensions must be greater than zero."
		}
	}
}

enum ImageSequenceLoader {
	static func isImage(_ url: URL) -> Bool {
		url.contentType?.conforms(to: .image) == true
	}

	static func loadCGImage(_ url: URL) throws -> CGImage {
		guard
			let source = CGImageSourceCreateWithURL(url as CFURL, nil),
			let image = CGImageSourceCreateImageAtIndex(
				source,
				0,
				[
					kCGImageSourceShouldCacheImmediately: true,
					kCGImageSourceShouldAllowFloat: true
				] as CFDictionary
			)
		else {
			throw ImageSequenceError.unreadableImage(url)
		}

		return image
	}

	static func normalizedImage(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
		guard width > 0, height > 0 else {
			throw ImageSequenceError.invalidDimensions
		}

		if image.width == width, image.height == height {
			return image
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

		context.interpolationQuality = .high
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

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

		guard job.outputWidth > 0, job.outputHeight > 0 else {
			throw ImageSequenceError.invalidDimensions
		}

		let orderedIndices: [Int] = {
			let forward = Array(job.urls.indices)
			guard job.bounce, job.urls.count > 1 else {
				return forward
			}

			return forward + Array((0..<(job.urls.count - 1)).reversed())
		}()

		let loop: Gifski.Loop = job.loop ? .forever : .never
		let gifski = try Gifski(
			dimensions: (job.outputWidth, job.outputHeight),
			quality: job.quality.clamped(to: 0.1...1),
			loop: loop
		)

		let frameRate = Double(job.frameRate.clamped(to: Int(Constants.allowedFrameRate.lowerBound)...Int(Constants.allowedFrameRate.upperBound)))
		let frameDuration = 1 / frameRate

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

		guard urls.count >= 2 else {
			error = ImageSequenceError.notEnoughImages
			return
		}

		let sortedURLs = urls.sorted {
			$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
		}

		for url in sortedURLs {
			_ = url.startAccessingSecurityScopedResource()
		}

		do {
			let firstImage = try ImageSequenceLoader.loadCGImage(sortedURLs[0])
			let job = ImageSequenceJob(
				urls: sortedURLs,
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
