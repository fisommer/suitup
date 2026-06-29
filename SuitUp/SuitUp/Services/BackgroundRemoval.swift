import UIKit
import Vision
import CoreImage

enum BackgroundRemoval {
    /// Returns a UIImage with the foreground subject isolated.
    /// Falls back to the original image if Vision can't find a subject.
    static func removeBackground(from image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return image }
            let maskBuffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            let ciImage = CIImage(cvPixelBuffer: maskBuffer)
            let context = CIContext()
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
                return image
            }
            return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        } catch {
            return image
        }
    }
}
