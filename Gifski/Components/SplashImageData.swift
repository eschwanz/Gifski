import AppKit
import Foundation

enum SplashImageData {
	static let base64 = [
		part00,
		part01,
		part02,
		part03,
		part04,
		part05,
		part06,
		part07
	].joined()

	static let image: NSImage? = {
		guard let data = Data(base64Encoded: base64) else {
			return nil
		}
		return NSImage(data: data)
	}()
}
