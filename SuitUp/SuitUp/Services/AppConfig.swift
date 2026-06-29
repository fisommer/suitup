import Foundation

enum AppConfig {
    /// Cloudflare Worker that crawls product URLs and returns structured data.
    /// Deployed via `wrangler deploy` from the `worker/` folder.
    static let crawlerBaseURL = URL(string: "https://suitup-crawler.yb4snpkzyn.workers.dev")!
}
