import SwiftUI

struct StartScreen: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		ZStack {
			SplashArtwork()
				.ignoresSafeArea()

			VStack {
				Spacer()

				VStack(spacing: 9) {
					if appState.isOpeningVideo {
						ProgressView("Opening…")
					} else {
						Text("Drop images or a video")
							.font(.headline)
						Text("Turn stills into a GIF or social-ready MP4.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
						Button("Choose Files…", systemImage: "plus") {
							appState.isFileImporterPresented = true
						}
						.buttonStyle(.borderedProminent)
						.controlSize(.large)
					}
				}
				.padding(.horizontal, 24)
				.padding(.vertical, 14)
				.background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
				.shadow(color: .black.opacity(0.08), radius: 20, y: 8)
				.padding(.bottom, 22)
			}
			.padding(.horizontal, 24)
		}
		.navigationTitle("")
	}
}

private struct SplashArtwork: View {
	private let cream = Color(red: 0.98, green: 0.96, blue: 0.90)
	private let coral = Color(red: 0.97, green: 0.43, blue: 0.48)
	private let pink = Color(red: 0.98, green: 0.30, blue: 0.55)
	private let blue = Color(red: 0.04, green: 0.31, blue: 0.72)
	private let cyan = Color(red: 0.05, green: 0.66, blue: 0.72)
	private let red = Color(red: 0.92, green: 0.08, blue: 0.10)
	private let yellow = Color(red: 1.00, green: 0.72, blue: 0.03)
	private let orange = Color(red: 1.00, green: 0.34, blue: 0.05)

	var body: some View {
		GeometryReader { proxy in
			let size = proxy.size

			ZStack {
				cream

				// Large floating planes from the approved artwork.
				plane(coral.opacity(0.86))
					.frame(width: size.width * 0.46, height: size.height * 0.18)
					.rotationEffect(.degrees(8))
					.position(x: size.width * 0.08, y: size.height * 0.22)

				plane(pink.opacity(0.80))
					.frame(width: size.width * 0.42, height: size.height * 0.15)
					.rotationEffect(.degrees(-7))
					.position(x: size.width * 0.90, y: size.height * 0.31)

				plane(coral.opacity(0.78))
					.frame(width: size.width * 0.64, height: size.height * 0.13)
					.rotationEffect(.degrees(8))
					.position(x: size.width * 0.24, y: size.height * 0.64)

				plane(pink.opacity(0.72))
					.frame(width: size.width * 0.40, height: size.height * 0.12)
					.rotationEffect(.degrees(-6))
					.position(x: size.width * 0.90, y: size.height * 0.70)

				// Sun and clouds.
				Circle()
					.fill(yellow)
					.frame(width: size.height * 0.25)
					.position(x: size.width * 0.95, y: size.height * 0.11)

				SplashCloud()
					.fill(red)
					.frame(width: size.width * 0.17, height: size.height * 0.10)
					.position(x: size.width * 0.80, y: size.height * 0.16)

				SplashCloud()
					.fill(red)
					.frame(width: size.width * 0.20, height: size.height * 0.11)
					.position(x: size.width * 0.12, y: size.height * 0.84)

				// Ladders.
				ladder
					.frame(width: 42, height: size.height * 0.42)
					.position(x: size.width * 0.18, y: size.height * 0.15)

				ladder
					.frame(width: 38, height: size.height * 0.46)
					.position(x: size.width * 0.84, y: size.height * 0.22)

				ladder
					.frame(width: 34, height: size.height * 0.34)
					.position(x: size.width * 0.23, y: size.height * 0.66)

				// Curved ribbons and orbit lines.
				Canvas { context, canvasSize in
					var longRibbon = Path()
					longRibbon.move(to: CGPoint(x: -40, y: canvasSize.height * 0.63))
					longRibbon.addCurve(
						to: CGPoint(x: canvasSize.width + 50, y: canvasSize.height * 0.72),
						control1: CGPoint(x: canvasSize.width * 0.30, y: canvasSize.height * 0.48),
						control2: CGPoint(x: canvasSize.width * 0.64, y: canvasSize.height * 0.92)
					)
					context.stroke(longRibbon, with: .color(coral), style: .init(lineWidth: max(24, canvasSize.height * 0.055), lineCap: .round))

					var yellowRibbon = Path()
					yellowRibbon.move(to: CGPoint(x: canvasSize.width * 0.67, y: canvasSize.height * 0.81))
					yellowRibbon.addCurve(
						to: CGPoint(x: canvasSize.width * 1.04, y: canvasSize.height * 0.53),
						control1: CGPoint(x: canvasSize.width * 0.82, y: canvasSize.height * 0.86),
						control2: CGPoint(x: canvasSize.width * 0.91, y: canvasSize.height * 0.55)
					)
					context.stroke(yellowRibbon, with: .color(yellow), style: .init(lineWidth: max(18, canvasSize.height * 0.038), lineCap: .round))

					for offset in [0.0, 0.18, 0.36] {
						var orbit = Path()
						orbit.move(to: CGPoint(x: canvasSize.width * (0.31 + offset), y: canvasSize.height * 0.18))
						orbit.addCurve(
							to: CGPoint(x: canvasSize.width * (0.52 + offset * 0.4), y: canvasSize.height * 0.36),
							control1: CGPoint(x: canvasSize.width * (0.42 + offset), y: canvasSize.height * 0.06),
							control2: CGPoint(x: canvasSize.width * (0.56 + offset * 0.5), y: canvasSize.height * 0.20)
						)
						context.stroke(orbit, with: .color(offset == 0 ? orange : coral.opacity(0.8)), lineWidth: 2)
					}
				}

				// Abstract geometric accents.
				SplashTriangle()
					.fill(red)
					.frame(width: 54, height: 58)
					.rotationEffect(.degrees(-8))
					.position(x: size.width * 0.64, y: size.height * 0.27)

				SplashTriangle()
					.fill(orange)
					.frame(width: 72, height: 84)
					.rotationEffect(.degrees(12))
					.position(x: size.width * 0.08, y: size.height * 0.47)

				Capsule()
					.fill(cyan)
					.frame(width: 66, height: 28)
					.rotationEffect(.degrees(48))
					.position(x: size.width * 0.74, y: size.height * 0.43)

				Capsule()
					.fill(yellow)
					.frame(width: 120, height: 22)
					.rotationEffect(.degrees(-27))
					.position(x: size.width * 0.56, y: size.height * 0.72)

				ForEach(Array(dotPositions.enumerated()), id: \.offset) { index, point in
					Circle()
						.fill(dotColors[index % dotColors.count])
						.frame(width: index.isMultiple(of: 3) ? 16 : 9)
						.position(x: size.width * point.x, y: size.height * point.y)
				}

				Text("Gif’in Stills")
					.font(.system(size: min(78, max(48, size.width * 0.085)), weight: .bold, design: .rounded))
					.foregroundStyle(Color(red: 0.05, green: 0.07, blue: 0.09))
					.tracking(-2)
					.position(x: size.width * 0.50, y: size.height * 0.46)
			}
			.clipped()
		}
	}

	private var ladder: some View {
		GeometryReader { proxy in
			ZStack {
				HStack {
					Rectangle().fill(blue).frame(width: 5)
					Spacer()
					Rectangle().fill(blue).frame(width: 5)
				}

				VStack(spacing: 10) {
					ForEach(0..<18, id: \.self) { _ in
						Rectangle()
							.fill(blue)
							.frame(height: 4)
					}
				}
				.padding(.vertical, 4)
			}
		}
	}

	private func plane(_ color: Color) -> some View {
		Rectangle()
			.fill(
				LinearGradient(
					colors: [color.opacity(0.92), color],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)
			)
			.shadow(color: .black.opacity(0.04), radius: 10, y: 5)
	}

	private var dotPositions: [CGPoint] {
		[
			.init(x: 0.07, y: 0.10),
			.init(x: 0.13, y: 0.36),
			.init(x: 0.30, y: 0.12),
			.init(x: 0.35, y: 0.30),
			.init(x: 0.42, y: 0.56),
			.init(x: 0.51, y: 0.31),
			.init(x: 0.68, y: 0.16),
			.init(x: 0.73, y: 0.60),
			.init(x: 0.82, y: 0.37),
			.init(x: 0.91, y: 0.51),
			.init(x: 0.95, y: 0.80),
			.init(x: 0.37, y: 0.79)
		]
	}

	private var dotColors: [Color] {
		[blue, orange, yellow, red, cyan]
	}
}


private struct SplashTriangle: Shape {
	func path(in rect: CGRect) -> Path {
		Path { path in
			path.move(to: CGPoint(x: rect.midX, y: rect.minY))
			path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
			path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
			path.closeSubpath()
		}
	}
}

private struct SplashCloud: Shape {
	func path(in rect: CGRect) -> Path {
		Path { path in
			path.addRoundedRect(
				in: CGRect(
					x: rect.minX + rect.width * 0.08,
					y: rect.minY + rect.height * 0.43,
					width: rect.width * 0.84,
					height: rect.height * 0.40
				),
				cornerSize: CGSize(width: rect.width * 0.20, height: rect.height * 0.20)
			)
			path.addEllipse(
				in: CGRect(
					x: rect.minX + rect.width * 0.18,
					y: rect.minY + rect.height * 0.18,
					width: rect.width * 0.34,
					height: rect.height * 0.52
				)
			)
			path.addEllipse(
				in: CGRect(
					x: rect.minX + rect.width * 0.42,
					y: rect.minY + rect.height * 0.08,
					width: rect.width * 0.38,
					height: rect.height * 0.62
				)
			)
		}
	}
}
