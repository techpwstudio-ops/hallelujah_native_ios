import PhotosUI
import SwiftUI
import UIKit

/// Camera capture (`ImagePicker().pickImage(source: ImageSource.camera)` in
/// `UploadPhoto._pickFromSource`). Returns a temp-file URL of the JPEG, or
/// `nil` when the user cancels. Needs `NSCameraUsageDescription` in Info.plist.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) else {
                onFinish(nil)
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            do {
                try data.write(to: url, options: .atomic)
                onFinish(url)
            } catch {
                onFinish(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

enum ProfileImageSupport {
    /// Copies a picked library item to a temp file the crop page can read.
    static func writeTempFile(from item: PhotosPickerItem) async -> URL? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).img")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// `FlutterImageCompress.compressWithFile(minWidth: 512, minHeight: 512, quality: 80)`
    /// then written to Documents as `<millis>.jpg`.
    static func compress(_ url: URL) -> URL? {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        let longest = min(image.size.width, image.size.height)
        let target: CGFloat = 512
        var output = image
        if longest > target {
            let ratio = target / longest
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        guard let jpeg = output.jpegData(compressionQuality: 0.8),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let destination = documents.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
        do {
            try jpeg.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }
}
