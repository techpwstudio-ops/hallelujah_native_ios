import SwiftUI
import UIKit

/// Ports `CropCompressImagePage` (`lib/views/crop_image_page.dart`): black
/// full-screen page, header (close / "Crop Image" / pink "Done" pill), crop
/// area with a 55% black scrim, white corner brackets and a rule-of-thirds
/// grid, and a `#111111` bottom toolbar with Reset / Rotate L / Rotate R.
///
/// Interaction deviation: Flutter's `crop_image` lets the user drag the crop
/// rectangle's handles; here the square crop frame is fixed and the picture
/// is panned / pinch-zoomed beneath it (the native idiom for a fixed
/// `aspectRatio`), with identical output (square PNG written to Documents).
struct CropImageView: View {
    let sourceURL: URL
    var aspectRatio: CGFloat = 1
    let onFinish: (URL?) -> Void

    @State private var baseImage: UIImage?
    @State private var rotationQuarterTurns = 0
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var frameSide: CGFloat = 0
    @State private var isProcessing = false
    @State private var failureMessage: String?

    private static let toolbarFill = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    private static let toolbarBorder = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255)
    /// `ColorTheme.pink` (0xFFCA4D53)
    private static let pink = Color(red: 0xCA / 255, green: 0x4D / 255, blue: 0x53 / 255)

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if isLandscape {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            header
                            cropArea
                        }
                        toolbar(horizontal: false)
                    }
                } else {
                    VStack(spacing: 0) {
                        header
                        cropArea
                        toolbar(horizontal: true)
                    }
                }
                if isProcessing {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView().tint(Color.white)
                }
                if let failureMessage {
                    VStack {
                        Spacer()
                        Text(failureMessage)
                            .font(AccountParity.bodyMedium)
                            .foregroundStyle(Color.black)
                            .padding(12)
                            .background(Capsule().fill(Color.white))
                            .padding(.bottom, 120)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { loadImage() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                onFinish(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Cancel")
            Text("Crop Image")
                .font(AccountParity.font(17, .semibold))
                .tracking(0.2)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
            Button {
                Task { await finish() }
            } label: {
                Text("Done")
                    .font(AccountParity.font(14, .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Self.pink))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
    }

    // MARK: Crop area

    private var displayImage: UIImage? {
        guard let baseImage else { return nil }
        return Self.rotated(baseImage, quarterTurns: rotationQuarterTurns)
    }

    private func cropSide(in size: CGSize) -> CGFloat {
        max(40, min(size.width - 24, size.height - 8) - 56)
    }

    private var cropArea: some View {
        GeometryReader { proxy in
            let side = cropSide(in: proxy.size)
            let frameWidth = side
            let frameHeight = side / max(aspectRatio, 0.01)
            ZStack {
                if let image = displayImage {
                    let cover = coverScale(for: image, width: frameWidth, height: frameHeight)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * cover * scale, height: image.size.height * cover * scale)
                        .offset(offset)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .gesture(dragGesture(image: image, width: frameWidth, height: frameHeight))
                        .simultaneousGesture(zoomGesture(image: image, width: frameWidth, height: frameHeight))
                }
                CropScrim(frameWidth: frameWidth, frameHeight: frameHeight)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                CropGrid(width: frameWidth, height: frameHeight)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear { frameSide = side }
            .onChange(of: proxy.size) { _, newSize in frameSide = cropSide(in: newSize) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func coverScale(for image: UIImage, width: CGFloat, height: CGFloat) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        return max(width / image.size.width, height / image.size.height)
    }

    private func clamp(_ proposed: CGSize, image: UIImage, width: CGFloat, height: CGFloat, scale: CGFloat) -> CGSize {
        let cover = coverScale(for: image, width: width, height: height)
        let maxX = max(0, (image.size.width * cover * scale - width) / 2)
        let maxY = max(0, (image.size.height * cover * scale - height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func dragGesture(image: UIImage, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = clamp(proposed, image: image, width: width, height: height, scale: scale)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func zoomGesture(image: UIImage, width: CGFloat, height: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(committedScale * value, 1), 8)
                offset = clamp(offset, image: image, width: width, height: height, scale: scale)
            }
            .onEnded { _ in
                committedScale = scale
                committedOffset = offset
            }
    }

    // MARK: Toolbar

    private func toolbar(horizontal: Bool) -> some View {
        Group {
            if horizontal {
                HStack {
                    Spacer()
                    toolbarButton("arrow.counterclockwise", "Reset") { reset() }
                    Spacer()
                    toolbarButton("rotate.left", "Rotate L") { rotate(by: -1) }
                    Spacer()
                    toolbarButton("rotate.right", "Rotate R") { rotate(by: 1) }
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .background(Self.toolbarFill)
                .overlay(alignment: .top) { Rectangle().fill(Self.toolbarBorder).frame(height: 1) }
            } else {
                VStack(spacing: 24) {
                    toolbarButton("arrow.counterclockwise", "Reset") { reset() }
                    toolbarButton("rotate.left", "Rotate L") { rotate(by: -1) }
                    toolbarButton("rotate.right", "Rotate R") { rotate(by: 1) }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 12)
                .frame(width: 88)
                .frame(maxHeight: .infinity)
                .background(Self.toolbarFill)
                .overlay(alignment: .leading) { Rectangle().fill(Self.toolbarBorder).frame(width: 1) }
            }
        }
    }

    private func toolbarButton(_ systemName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white)
                    .padding(11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AccountParity.white12, lineWidth: 1)
                    )
                Text(label)
                    .font(AccountParity.font(11))
                    .tracking(0.1)
                    .foregroundStyle(AccountParity.white54)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func loadImage() {
        guard baseImage == nil,
              let data = try? Data(contentsOf: sourceURL),
              let image = UIImage(data: data) else { return }
        baseImage = Self.normalized(image)
    }

    private func reset() {
        withAnimation(.easeOut(duration: 0.2)) {
            rotationQuarterTurns = 0
            scale = 1
            committedScale = 1
            offset = .zero
            committedOffset = .zero
        }
    }

    private func rotate(by turns: Int) {
        rotationQuarterTurns = ((rotationQuarterTurns + turns) % 4 + 4) % 4
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }

    @MainActor
    private func finish() async {
        guard !isProcessing, let image = displayImage else {
            fail()
            return
        }
        isProcessing = true
        let result = Self.render(
            image: image,
            aspectRatio: aspectRatio,
            scale: scale,
            offset: offset,
            frameSide: frameSide
        )
        isProcessing = false
        if let result {
            onFinish(result)
        } else {
            fail()
        }
    }

    private func fail() {
        failureMessage = "Image processing failed"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            failureMessage = nil
        }
    }

    // MARK: Image helpers

    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    private static func rotated(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let swap = turns % 2 == 1
        let newSize = swap ? CGSize(width: image.size.height, height: image.size.width) : image.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    /// Crops `image` to the frame the user framed and writes a PNG to
    /// Documents (`<millis>.png`, as `_finished` does).
    private static func render(image: UIImage, aspectRatio: CGFloat, scale: CGFloat, offset: CGSize, frameSide: CGFloat) -> URL? {
        let frameWidth = frameSide
        let frameHeight = frameSide / max(aspectRatio, 0.01)
        guard image.size.width > 0, image.size.height > 0, frameWidth > 0 else { return nil }
        let cover = max(frameWidth / image.size.width, frameHeight / image.size.height)
        let displayScale = cover * scale
        let cropWidth = frameWidth / displayScale
        let cropHeight = frameHeight / displayScale
        let centerX = image.size.width / 2 - offset.width / displayScale
        let centerY = image.size.height / 2 - offset.height / displayScale
        let originX = min(max(centerX - cropWidth / 2, 0), max(0, image.size.width - cropWidth))
        let originY = min(max(centerY - cropHeight / 2, 0), max(0, image.size.height - cropHeight))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropWidth, height: cropHeight), format: format)
        let output = renderer.image { _ in
            image.draw(at: CGPoint(x: -originX, y: -originY))
        }
        guard let data = output.pngData(),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = documents.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000)).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Overlay shapes

/// Full rect with the crop frame cut out (even-odd fill) = the 0.55 scrim.
private struct CropScrim: Shape {
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(CGRect(
            x: rect.midX - frameWidth / 2,
            y: rect.midY - frameHeight / 2,
            width: frameWidth,
            height: frameHeight
        ))
        return path
    }
}

/// Rule-of-thirds grid (white54, 1pt), outline, and 28pt corner brackets (white, 2.5pt).
private struct CropGrid: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Path { path in
                for i in 1...2 {
                    let x = width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    let y = height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(AccountParity.white54, lineWidth: 1)
            Rectangle().strokeBorder(AccountParity.white54, lineWidth: 1)
            Path { path in
                let length: CGFloat = 28
                // top-left
                path.move(to: CGPoint(x: 0, y: length)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: length, y: 0))
                // top-right
                path.move(to: CGPoint(x: width - length, y: 0)); path.addLine(to: CGPoint(x: width, y: 0)); path.addLine(to: CGPoint(x: width, y: length))
                // bottom-right
                path.move(to: CGPoint(x: width, y: height - length)); path.addLine(to: CGPoint(x: width, y: height)); path.addLine(to: CGPoint(x: width - length, y: height))
                // bottom-left
                path.move(to: CGPoint(x: length, y: height)); path.addLine(to: CGPoint(x: 0, y: height)); path.addLine(to: CGPoint(x: 0, y: height - length))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
        }
        .frame(width: width, height: height)
    }
}
