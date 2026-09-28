import AVFoundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Gifski

struct ImageSequenceTests {
	@Test
	func bounceFrameOrder() {
		let urls = (0..<4).map { URL(filePath: "/tmp/frame\($0).png") }
		let job = ImageSequenceJob(
			urls: urls,
			bounce: true,
			outputWidth: 64,
			outputHeight: 64
		)

		#expect(job.frameIndices == [0, 1, 2, 3, 2, 1, 0])
		#expect(abs(job.duration - 0.7) < 0.0001)
	}

	@Test
	func normalizationPreservesAspectRatioWithTransparentPadding() throws {
		let source = try makeImage(width: 80, height: 40)
		let result = try ImageSequenceLoader.normalizedImage(source, width: 100, height: 100)

		#expect(result.width == 100)
		#expect(result.height == 100)

		let data = try #require(result.dataProvider?.data)
		let bytes = try #require(CFDataGetBytePtr(data))
		let rowBytes = result.bytesPerRow

		// The top-left pixel is outside the aspect-fit image and should remain transparent.
		#expect(bytes[3] == 0)

		// The center pixel is inside the source image and should be opaque.
		let centerOffset = (50 * rowBytes) + (50 * 4)
		#expect(bytes[centerOffset + 3] == 255)
	}

	@Test
	func imageLoaderAppliesOrientationMetadata() throws {
		let directory = try URL.uniqueTemporaryDirectory()
		defer { try? directory.delete() }

		let url = directory.appending(path: "rotated.jpg")
		let image = try makeImage(width: 80, height: 40)
		guard let destination = CGImageDestinationCreateWithURL(
			url as CFURL,
			UTType.jpeg.identifier as CFString,
			1,
			nil
		) else {
			throw ImageSequenceError.unreadableImage(url)
		}

		CGImageDestinationAddImage(
			destination,
			image,
			[kCGImagePropertyOrientation: 6] as CFDictionary
		)
		try #require(CGImageDestinationFinalize(destination))

		let loaded = try ImageSequenceLoader.loadCGImage(url)
		#expect(loaded.width == 40)
		#expect(loaded.height == 80)
	}

	@Test
	func gifSequenceSmokeTest() async throws {
		let fixture = try makeFrameSequence()
		defer { try? fixture.directory.delete() }

		let job = ImageSequenceJob(
			urls: fixture.urls,
			frameRate: 10,
			outputWidth: 64,
			outputHeight: 64
		)

		let data = try await ImageSequenceGenerator.run(job) { _ in }
		#expect(data.starts(with: Data("GIF8".utf8)))

		let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
		#expect(CGImageSourceGetCount(source) == 2)
	}

	@Test
	func mp4SequenceSmokeTestIncludesFinalFrameDuration() async throws {
		let fixture = try makeFrameSequence()
		defer { try? fixture.directory.delete() }

		let job = ImageSequenceJob(
			urls: fixture.urls,
			frameRate: 10,
			outputWidth: 64,
			outputHeight: 64,
			outputFormat: .mp4
		)

		let outputURL = try await ImageSequenceVideoExporter.run(job) { _ in }
		defer { try? outputURL.delete() }

		let asset = AVURLAsset(url: outputURL)
		let duration = try await asset.load(.duration)
		#expect(abs(duration.seconds - 0.2) < 0.03)

		let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
		let size = try await track.load(.naturalSize)
		#expect(Int(size.width) == 64)
		#expect(Int(size.height) == 64)
	}

	private func makeFrameSequence() throws -> (directory: URL, urls: [URL]) {
		let directory = try URL.uniqueTemporaryDirectory()
		let urls = [
			directory.appending(path: "frame1.png"),
			directory.appending(path: "frame2.png")
		]

		try writePNG(try makeImage(width: 80, height: 40, red: 255), to: urls[0])
		try writePNG(try makeImage(width: 40, height: 80, green: 255), to: urls[1])
		return (directory, urls)
	}

	private func makeImage(
		width: Int,
		height: Int,
		red: UInt8 = 0,
		green: UInt8 = 0,
		blue: UInt8 = 0
	) throws -> CGImage {
		guard let context = CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		) else {
			throw ImageSequenceError.invalidDimensions
		}

		context.setFillColor(
			CGColor(
				red: Double(red) / 255,
				green: Double(green) / 255,
				blue: Double(blue) / 255,
				alpha: 1
			)
		)
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		return try #require(context.makeImage())
	}

	private func writePNG(_ image: CGImage, to url: URL) throws {
		guard let destination = CGImageDestinationCreateWithURL(
			url as CFURL,
			UTType.png.identifier as CFString,
			1,
			nil
		) else {
			throw ImageSequenceError.unreadableImage(url)
		}

		CGImageDestinationAddImage(destination, image, nil)
		try #require(CGImageDestinationFinalize(destination))
	}
}
