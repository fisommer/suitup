import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum BackgroundRemoval {
    enum Outcome {
        case removed(UIImage)
        case noSubjectFound(UIImage)   // returns original
        case failed(Error, UIImage)    // returns original
    }

    /// Returns the outcome of background removal. Falls back to the original image
    /// when Vision doesn't find a subject (e.g., low-contrast studio photography).
    static func attemptRemoval(from image: UIImage) async -> Outcome {
        guard let cgImage = image.cgImage else {
            print("[BackgroundRemoval] No CGImage on input")
            return .noSubjectFound(image)
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                print("[BackgroundRemoval] No subject found by Vision — using original")
                return .noSubjectFound(image)
            }
            print("[BackgroundRemoval] Found \(result.allInstances.count) subject(s)")

            // Compose: use the result's masked image (CVPixelBuffer of RGBA),
            // convert via CIImage with proper context settings.
            let maskBuffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )

            let ciImage = CIImage(cvPixelBuffer: maskBuffer)
            let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any])
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
                print("[BackgroundRemoval] Failed to create CGImage from mask buffer — using original")
                return .noSubjectFound(image)
            }
            let removed = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
            print("[BackgroundRemoval] Success — output size \(removed.size)")
            return .removed(removed)
        } catch {
            print("[BackgroundRemoval] Vision error: \(error)")
            return .failed(error, image)
        }
    }

    /// Convenience: returns either the bg-removed image or the original.
    static func removeBackground(from image: UIImage) async -> UIImage {
        let outcome = await attemptRemoval(from: image)
        switch outcome {
        case .removed(let img), .noSubjectFound(let img), .failed(_, let img):
            return img
        }
    }
}
