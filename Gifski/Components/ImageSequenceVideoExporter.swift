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

		let width = max(2, job.outputWidth - (job.outputWidth % 2))
		let height = max(2, job.outputHeight - (job.outputHeight % 2))
		let fps = job.frameRate.clamped(to: 3...50)
		let outputURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
		try? outputURL.delete()

		let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
		let bitrate = recommendedBitrate(width: width, height: height, frameRate: fps)
		let settings: [String: Any] = [
			AVVideoCodecKey: AVVideoCodecType.h264,
			AVVideoWidthKey: width,
			AVVideoHeightKey: height,
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
			throw ImageSequenceVideoExporterError.exportFailed(writer.error?.localizedDescription ?? "Unknown error")
		}
		writer.startSession(atSourceTime: .zero)

		let indices: [Int] = {
			let forward = Array(job.urls.indices)
			guard job.bounce, job.urls.count > 1 else {
				return forward
			}
			return forward + Array((0..<(job.urls.count - 1)).reversed())
		}()

		for (outputIndex, sourceIndex) in indices.enumerated() {
			try Task.checkCancellation()

			while !input.isReadyForMoreMediaData {
				try Task.checkCancellation()
				try await Task.sleep(for: .milliseconds(5))
			}

			let source = try ImageSequenceLoader.loadCGImage(job.urls[sourceIndex])
			let normalized = try ImageSequenceLoader.normalizedImage(source, width: width, height: height)
			let pixelBuffer = try makePixelBuffer(from: normalized, width: width, height: height)
			let time = CMTime(value: CMTimeValue(outputIndex), timescale: CMTimeScale(fps))

			guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
				throw ImageSequenceVideoExporterError.appendFailed
			}

			onProgress(Double(outputIndex + 1) / Double(indices.count))
		}

		input.markAsFinished()
		await writer.finishWriting()

		guard writer.status == .completed else {
			throw ImageSequenceVideoExporterError.exportFailed(writer.error?.localizedDescription ?? "Unknown error")
		}

		return outputURL
	}

	private static func recommendedBitrate(width: Int, height: Int, frameRate: Int) -> Int {
		let pixels = Double(width * height)
		let fpsFactor = Double(frameRate) / 30.0
		let bitsPerPixelPerFrame = 0.10
		let calculated = Int(pixels * Double(frameRate) * bitsPerPixelPerFrame)
		let floor = Int(4_000_000 * max(1, fpsFactor))
		let ceiling = 20_000_000
		return calculated.clamped(to: floor...ceiling)
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
