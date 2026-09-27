import AVFoundation
import CoreGraphics
import CoreTransferable
import CoreVideo
import Foundation
import UniformTypeIdentifiers

enum ImageSequenceVideoExporterError: LocalizedError {
	case cannotCreateWriter
	case cannotCreatePixelBuffer
	case appendFailed
	case exportFailed(String)

	var errorDescription: String? {
		switch self {
		case .cannotCreateWriter:
			"Could not create the MP4 encoder."
		case .cannotCreatePixelBuffer:
			"Could not prepare an image frame for MP4 export."
		case .appendFailed:
			"A frame could not be written to the MP4."
		case .exportFailed(let message):
			"MP4 export failed: \(message)"
		}
	}
}

actor ImageSequenceVideoExporter {
	static func run(
		_ job: ImageSequenceJob,
		onProgress: @escaping @Sendable (Double) -> Void
	) async throws -> URL {
		guard job.urls.count >= 2 else {
			throw ImageSequenceError.notEnoughImages
		}

		let dimensions = job.effectiveMP4Dimensions
		guard dimensions.width >= 2, dimensions.height >= 2 else {
			throw ImageSequenceError.invalidDimensions
		}

		let width = dimensions.width
		let height = dimensions.height
		let fps = job.frameRate.clamped(to: 3...50)
		let outputURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
		try? outputURL.delete()

		var didFinishSuccessfully = false
		defer {
			if !didFinishSuccessfully {
				try? outputURL.delete()
			}
		}

		let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
		let bitrate = recommendedBitrate(width: width, height: height, frameRate: fps)
		let settings: [String: Any] = [
			AVVideoCodecKey: AVVideoCodecType.h264,
			AVVideoWidthKey: width,
			AVVideoHeightKey: height,
			AVVideoColorPropertiesKey: [
				AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
				AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
				AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
			],
			AVVideoCompressionPropertiesKey: [
				AVVideoAverageBitRateKey: bitrate,
				AVVideoMaxKeyFrameIntervalKey: fps * 2,
				AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
			]
		]

		let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
		input.expectsMediaDataInRealTime = false

		let attributes: [String: Any] = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
			kCVPixelBufferWidthKey as String: width,
			kCVPixelBufferHeightKey as String: height,
			kCVPixelBufferCGImageCompatibilityKey as String: true,
			kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
		]

		let adaptor = AVAssetWriterInputPixelBufferAdaptor(
			assetWriterInput: input,
			sourcePixelBufferAttributes: attributes
		)

		guard writer.canAdd(input) else {
			throw ImageSequenceVideoExporterError.cannotCreateWriter
		}

		writer.add(input)
		guard writer.startWriting() else {
			throw writerError(writer)
		}
		writer.startSession(atSourceTime: .zero)

		let indices = job.frameIndices
		for (outputIndex, sourceIndex) in indices.enumerated() {
			try Task.checkCancellation()

			while !input.isReadyForMoreMediaData {
				try Task.checkCancellation()
				try throwIfWriterStopped(writer)
				try await Task.sleep(for: .milliseconds(5))
			}

			try throwIfWriterStopped(writer)

			let source = try ImageSequenceLoader.loadCGImage(job.urls[sourceIndex])
			let normalized = try ImageSequenceLoader.normalizedImage(source, width: width, height: height)
			let pixelBuffer = try makePixelBuffer(from: normalized, width: width, height: height)
			let time = CMTime(value: CMTimeValue(outputIndex), timescale: CMTimeScale(fps))

			guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
				throw writer.error.map { ImageSequenceVideoExporterError.exportFailed($0.localizedDescription) }
					?? ImageSequenceVideoExporterError.appendFailed
			}

			onProgress(Double(outputIndex + 1) / Double(indices.count))
		}

		// Give the last still a full frame duration instead of ending the movie at its presentation timestamp.
		writer.endSession(atSourceTime: CMTime(value: CMTimeValue(indices.count), timescale: CMTimeScale(fps)))
		input.markAsFinished()
		await writer.finishWriting()

		guard writer.status == .completed else {
			throw writerError(writer)
		}

		didFinishSuccessfully = true
		return outputURL
	}

	private static func throwIfWriterStopped(_ writer: AVAssetWriter) throws {
		switch writer.status {
		case .failed, .cancelled:
			throw writerError(writer)
		default:
			break
		}
	}

	private static func writerError(_ writer: AVAssetWriter) -> ImageSequenceVideoExporterError {
		.exportFailed(writer.error?.localizedDescription ?? "The encoder stopped unexpectedly.")
	}

	private static func recommendedBitrate(width: Int, height: Int, frameRate: Int) -> Int {
		let calculated = Int(Double(width * height * frameRate) * 0.08)
		return calculated.clamped(to: 2_000_000...12_000_000)
	}

	private static func makePixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			width,
			height,
			kCVPixelFormatType_32BGRA,
			[
				kCVPixelBufferCGImageCompatibilityKey: true,
				kCVPixelBufferCGBitmapContextCompatibilityKey: true
			] as CFDictionary,
			&pixelBuffer
		)

		guard status == kCVReturnSuccess, let pixelBuffer else {
			throw ImageSequenceVideoExporterError.cannotCreatePixelBuffer
		}

		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

		guard
			let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
			let context = CGContext(
				data: baseAddress,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
				space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
			)
		else {
			throw ImageSequenceVideoExporterError.cannotCreatePixelBuffer
		}

		// H.264 has no alpha channel, so transparent source padding becomes white rather than black.
		context.setFillColor(CGColor(gray: 1, alpha: 1))
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		return pixelBuffer
	}
}

struct ExportableMP4: Transferable {
	let url: URL

	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation(exportedContentType: .mpeg4Movie) { .init($0.url) }
			.suggestedFileName { $0.url.filename }
	}
}
