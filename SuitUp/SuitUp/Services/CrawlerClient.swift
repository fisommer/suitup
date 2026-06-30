import Foundation
import UIKit

struct CrawlResult: Decodable {
    struct DataBlock: Decodable {
        let name: String?
        let brand: String?
        let category: String?
        let colors: [String]?
        let materials: [String]?
        let price: Price?
        let availableSizes: [String]?
        let description: String?
        /// Readable color name corresponding to the variant the user picked via URL query.
        /// Resolved either via JSON-LD `hasVariant` or by the vision-pass reconciliation.
        let selectedColor: String?
        /// Same idea for size.
        let selectedSize: String?

        struct Price: Decodable {
            let value: Double
            let currency: String
        }
    }

    let success: Bool
    let images: [String]
    let data: DataBlock
    let warnings: [String]
    let error: String?
}

enum CrawlerError: Error, LocalizedError {
    case http(Int, String)
    case decoding(String)
    case noImages
    case noResults(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "Crawler returned HTTP \(code): \(body.prefix(200))"
        case .decoding(let s):
            return "Couldn't parse crawler response: \(s)"
        case .noImages:
            return "No product images found at that URL."
        case .noResults(let s):
            return "Crawl failed: \(s)"
        }
    }
}

struct CrawlerClient {
    func crawl(url: String) async throws -> CrawlResult {
        var req = URLRequest(url: AppConfig.crawlerBaseURL.appendingPathComponent("crawl"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(["url": url])
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CrawlerError.http(http.statusCode, body)
        }
        do {
            let result = try JSONDecoder().decode(CrawlResult.self, from: data)
            if !result.success, let err = result.error {
                throw CrawlerError.noResults(err)
            }
            return result
        } catch let err as CrawlerError {
            throw err
        } catch {
            throw CrawlerError.decoding(error.localizedDescription)
        }
    }

    func downloadImage(_ urlString: String) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw CrawlerError.decoding("invalid url")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CrawlerError.http(http.statusCode, "image fetch failed")
        }
        guard let img = UIImage(data: data) else {
            throw CrawlerError.decoding("not an image")
        }
        return img
    }
}
