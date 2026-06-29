import Foundation
import UIKit

enum AnthropicError: Error, LocalizedError {
    case missingKey
    case httpError(Int, String)
    case parseError(String)
    case noToolUse

    var errorDescription: String? {
        switch self {
        case .missingKey: "Anthropic API key not configured. Add it in Settings."
        case .httpError(let code, let body): "Anthropic API error \(code): \(body.prefix(200))"
        case .parseError(let s): "Could not parse response: \(s)"
        case .noToolUse: "Model did not return a tool call."
        }
    }
}

/// Generic Claude messages-API client supporting tool_use for structured output.
struct AnthropicClient {
    enum ContentBlock {
        case text(String)
        case image(UIImage)
    }

    let model: String = "claude-sonnet-latest"
    let maxTokens: Int = 2048

    /// Force the model to call a single tool. Returns the tool's `input` dict.
    func callTool(
        system: String,
        toolName: String,
        toolDescription: String,
        toolInputSchema: [String: Any],
        userBlocks: [ContentBlock]
    ) async throws -> [String: Any] {
        guard let apiKey = KeychainStore.get(), !apiKey.isEmpty else {
            throw AnthropicError.missingKey
        }

        let contentJSON: [[String: Any]] = userBlocks.map { block in
            switch block {
            case .text(let s):
                return ["type": "text", "text": s]
            case .image(let img):
                let data = img.jpegData(compressionQuality: 0.85) ?? Data()
                let b64 = data.base64EncodedString()
                return [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": b64,
                    ],
                ]
            }
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "tools": [[
                "name": toolName,
                "description": toolDescription,
                "input_schema": toolInputSchema,
            ]],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [["role": "user", "content": contentJSON]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.parseError("no http response")
        }
        if http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AnthropicError.httpError(http.statusCode, bodyStr)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]]
        else {
            throw AnthropicError.parseError("malformed body")
        }
        guard
            let toolUse = content.first(where: { ($0["type"] as? String) == "tool_use" }),
            let input = toolUse["input"] as? [String: Any]
        else {
            throw AnthropicError.noToolUse
        }
        return input
    }
}
