import SwiftUI
import UIKit

/// Ports `CropCompressImagePage` (`lib/views/crop_image_page.dart`): black
/// full-screen page, header (close / "Crop Image" / pink "Done" pill), crop
/// area with a 55% black scrim, white corner brackets and a rule-of-thirds
/// grid, and a `#111111` bottom toolbar with Reset / Rotate L / Rotate R.
///
/// Behaves like the `crop_image` package Flutter uses: the whole photo is
/// fitted inside the area (28pt padding), and the crop box sits on top of
/// it — drag a corner to resize it (the aspect ratio stays fixed), drag
/// anywhere else to move it (`alwaysMove: true`). It starts as the largest
/// box of that ratio the photo allows. Output: the boxed pixels as a PNG
/// in Documents (`<millis>.png`), as `_finished` writes.
struct CropImageView: View {
    let sourceURL: URL
    var aspectRatio: CGFloat = 1
    let onFinish: (URL?) -> Void

    @State private var baseImage: UIImage?
    @State private var rotationQuarterTurns = 0
    /// `baseImage` turned by `rotationQuarterTurns`. Kept, not computed:
    /// re-rotating a full-size photo on every drag frame stalls the gesture.
    @State private var displayImage: UIImage?
    /// The crop box in unit coordinates of `displayImage` (0...1 on each axis).
    @State private var cropRect: CGRect = .zero
    @State private var dragStart: CropDragStart?
    @State private var isProcessing = false
    @State private var failureMessage: String?

    /// `CropImage(paddingSize: 28)`.
    private static let imagePadding: CGFloat = 28
    /// How close to a corner a touch must start to resize rather than move.
    private static let cornerHitRadius: CGFloat = 36
    /// Smallest box side on screen.
    private static let minimumCropSide: CGFloat = 48

    private static let toolbarFill = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    private static let toolbarBorder = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255)
    /// `ColorTheme.pink` (0xFFCA4D53)
    private static let pink = Color(red: 0xCA / 255, green: 0x4D / 255, blue: 0x53 / 255)

    /// The device's real safe-area insets, read from the window. The page
    /// lays itself out edge to edge and pads by these explicitly: relying on
    /// SwiftUI's safe area left the header under the status bar on device
    /// (twice), so it no longer depends on what the presentation reports.
    private static var windowInsets: UIEdgeInsets {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.safeAreaInsets ?? .zero
    }

    var body: some View {
        let insets = Self.windowInsets
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            ZStack {
                if isLandscape {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            header.zIndex(1)
                            cropArea
                        }
                        toolbar(horizontal: false)
                    }
                } else {
                    VStack(spacing: 0) {
                        header.zIndex(1)
                        cropArea
                        toolbar(horizontal: true).zIndex(1)
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
        .padding(.top, insets.top)
        .padding(.bottom, insets.bottom)
        .padding(.leading, insets.left)
        .padding(.trailing, insets.right)
        .background(Color.black)
        .ignoresSafeArea()
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


    /// Where the fitted photo sits inside the crop area.
    private func imageFrame(for image: UIImage, in size: CGSize) -> CGRect {
        let available = CGSize(
            width: max(1, size.width - Self.imagePadding * 2),
            height: max(1, size.height - Self.imagePadding * 2)
        )
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let fit = min(available.width / image.size.width, available.height / image.size.height)
        let fitted = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func screenRect(of unitRect: CGRect, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + unitRect.minX * imageFrame.width,
            y: imageFrame.minY + unitRect.minY * imageFrame.height,
            width: unitRect.width * imageFrame.width,
            height: unitRect.height * imageFrame.height
        )
    }

    private var cropArea: some View {
        GeometryReader { proxy in
            if let image = displayImage {
                let frame = imageFrame(for: image, in: proxy.size)
                let box = screenRect(of: cropRect, in: frame)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                    CropScrim(cutout: box)
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    CropGrid(width: box.width, height: box.height)
                        .offset(x: box.minX, y: box.minY)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .allowsHitTesting(false)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(cropDragGesture(image: image, imageFrame: frame))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// The largest box of `aspectRatio` (width / height, in pixels) the
    /// photo allows, centred — `CropController`'s full-image default after
    /// `_adjustRatio`.
    private static func defaultCrop(for image: UIImage, aspectRatio: CGFloat) -> CGRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let ratio = max(aspectRatio, 0.01)
        let width = min(size.width, size.height * ratio)
        let height = width / ratio
        return CGRect(
            x: (size.width - width) / 2 / size.width,
            y: (size.height - height) / 2 / size.height,
            width: width / size.width,
            height: height / size.height
        )
    }

    private func cropDragGesture(image: UIImage, imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard imageFrame.width > 0, imageFrame.height > 0 else { return }
                if dragStart == nil {
                    dragStart = CropDragStart(
                        rect: cropRect,
                        corner: corner(near: value.startLocation, box: screenRect(of: cropRect, in: imageFrame))
                    )
                }
                guard let start = dragStart else { return }
                let delta = CGSize(
                    width: value.translation.width / imageFrame.width,
                    height: value.translation.height / imageFrame.height
                )
                if let corner = start.corner {
                    cropRect = resized(start.rect, corner: corner, by: delta, image: image, imageFrame: imageFrame)
                } else {
                    cropRect = moved(start.rect, by: delta)
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    private func corner(near point: CGPoint, box: CGRect) -> CropCorner? {
        let corners: [(CropCorner, CGPoint)] = [
            (.topLeft, CGPoint(x: box.minX, y: box.minY)),
            (.topRight, CGPoint(x: box.maxX, y: box.minY)),
            (.bottomLeft, CGPoint(x: box.minX, y: box.maxY)),
            (.bottomRight, CGPoint(x: box.maxX, y: box.maxY)),
        ]
        let nearest = corners.min { hypot($0.1.x - point.x, $0.1.y - point.y) < hypot($1.1.x - point.x, $1.1.y - point.y) }
        guard let nearest, hypot(nearest.1.x - point.x, nearest.1.y - point.y) <= Self.cornerHitRadius else { return nil }
        return nearest.0
    }

    private func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.minX + delta.width, 0), 1 - rect.width)
        result.origin.y = min(max(rect.minY + delta.height, 0), 1 - rect.height)
        return result
    }

    /// Resizes from `corner`, keeping the opposite corner fixed and the
    /// box's pixel aspect ratio, within the photo and above a minimum size.
    /// Worked in pixels: unit coordinates aren't square on a non-square photo.
    private func resized(_ rect: CGRect, corner: CropCorner, by delta: CGSize, image: UIImage, imageFrame: CGRect) -> CGRect {
        let size = image.size
        let ratio = max(aspectRatio, 0.01)
        let pixels = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                            width: rect.width * size.width, height: rect.height * size.height)
        let movesLeft = corner == .topLeft || corner == .bottomLeft
        let movesUp = corner == .topLeft || corner == .topRight
        let anchor = CGPoint(x: movesLeft ? pixels.maxX : pixels.minX, y: movesUp ? pixels.maxY : pixels.minY)
        let dragged = CGPoint(
            x: (movesLeft ? pixels.minX : pixels.maxX) + delta.width * size.width,
            y: (movesUp ? pixels.minY : pixels.maxY) + delta.height * size.height
        )
        let proposedWidth = movesLeft ? anchor.x - dragged.x : dragged.x - anchor.x
        let proposedHeight = movesUp ? anchor.y - dragged.y : dragged.y - anchor.y
        var width = max(proposedWidth, proposedHeight * ratio)

        let maxWidth = min(
            movesLeft ? anchor.x : size.width - anchor.x,
            (movesUp ? anchor.y : size.height - anchor.y) * ratio
        )
        let pixelsPerPoint = size.width / imageFrame.width
        let minWidth = min(Self.minimumCropSide * pixelsPerPoint * max(ratio, 1), maxWidth)
        width = min(max(width, minWidth), maxWidth)
        let height = width / ratio

        let originX = movesLeft ? anchor.x - width : anchor.x
        let originY = movesUp ? anchor.y - height : anchor.y
        return CGRect(x: originX / size.width, y: originY / size.height,
                      width: width / size.width, height: height / size.height)
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

    private func toolbarButton(_ systemName: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
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
        let normalized = Self.normalized(image)
        baseImage = normalized
        displayImage = normalized
        cropRect = Self.defaultCrop(for: normalized, aspectRatio: aspectRatio)
    }

    private func reset() {
        rotationQuarterTurns = 0
        displayImage = baseImage
        resetCrop()
    }

    private func rotate(by turns: Int) {
        rotationQuarterTurns = ((rotationQuarterTurns + turns) % 4 + 4) % 4
        if let baseImage {
            displayImage = Self.rotated(baseImage, quarterTurns: rotationQuarterTurns)
        }
        resetCrop()
    }

    private func resetCrop() {
        guard let image = displayImage else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            cropRect = Self.defaultCrop(for: image, aspectRatio: aspectRatio)
        }
    }

    @MainActor
    private func finish() async {
        guard !isProcessing, let image = displayImage else {
            fail()
            return
        }
        isProcessing = true
        let result = Self.render(image: image, unitCrop: cropRect)
        isProcessing = false
        if let result {
            onFinish(result)
        } else {
            fail()
        }
    }

    private func fail() {
        failureMessage = String(localized: "Image processing failed")
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

    /// Crops `image` to the box the user set and writes a PNG to
    /// Documents (`<millis>.png`, as `_finished` does).
    private static func render(image: UIImage, unitCrop: CGRect) -> URL? {
        let size = image.size
        guard size.width > 0, size.height > 0, unitCrop.width > 0, unitCrop.height > 0 else { return nil }
        let crop = CGRect(
            x: unitCrop.minX * size.width,
            y: unitCrop.minY * size.height,
            width: unitCrop.width * size.width,
            height: unitCrop.height * size.height
        ).integral.intersection(CGRect(origin: .zero, size: size))
        guard crop.width >= 1, crop.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
        let output = renderer.image { _ in
            image.draw(at: CGPoint(x: -crop.minX, y: -crop.minY))
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

/// Full rect with the crop box cut out (even-odd fill) = the 0.55 scrim.
private struct CropScrim: Shape {
    let cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cutout)
        return path
    }
}

private enum CropCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// The box as it was when a drag began, and the corner being dragged
/// (`nil` = moving the whole box).
private struct CropDragStart {
    let rect: CGRect
    let corner: CropCorner?
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
