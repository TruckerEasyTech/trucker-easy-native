import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

private func agentLogAIService(
    runId: String,
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: Any] = [:]
) {
    let payload: [String: Any] = [
        "sessionId": "ff95f6",
        "runId": runId,
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          var line = String(data: json, encoding: .utf8) else { return }
    line.append("\n")
    DeveloperDebugLog.appendNDJSONLine(line)
}

// MARK: - AI Service
// Primary:  Apple Foundation Models (on-device, private, iOS 18+)
// Fallback: OpenRouter free-tier (cloud, works on any device with internet)

@Observable
final class AIService {
    static let shared = AIService()

    // MARK: - Configuration

    private let apiKey: String
    private let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let openRouterModel = "mistralai/mistral-7b-instruct:free"

    /// System prompt shared between both providers
    private let systemPrompt = """
    You are Route Easy, the routing assistant inside Trucker Easy for professional truck drivers. \
    Help compare routes: time, estimated tolls, fuel cost, and truck restrictions. \
    Also help with HOS, truck stops, weight limits, DOT rules, and weather. \
    When the navigation context lists tolls or diesel, use those numbers — do not invent prices. \
    Be concise and practical. Respond in the same language the driver uses.
    """

    private init() {
        apiKey = Bundle.main.object(forInfoDictionaryKey: "OpenRouterAPIKey") as? String ?? ""
    }

    // MARK: - Public API

    /// Streams a response to `message`, using Foundation Models when available and
    /// falling back to OpenRouter otherwise. Yields incremental text chunks.
    func streamResponse(to message: String, context: [String]) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability {
                agentLogAIService(
                    runId: "post-fix",
                    hypothesisId: "H7",
                    location: "ServicesAIService.swift:streamResponse",
                    message: "Using Foundation Models provider",
                    data: [:]
                )
                return streamWithFoundationModels(message: message, context: context)
            }
        }
        #endif
        if apiKey.isEmpty {
            agentLogAIService(
                runId: "post-fix",
                hypothesisId: "H7",
                location: "ServicesAIService.swift:streamResponse",
                message: "AI unavailable: no on-device model + missing OpenRouterAPIKey",
                data: ["foundationModelsAvailable": false]
            )
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AIError.serviceUnavailable(
                    "No on-device model available and OpenRouterAPIKey is missing."
                ))
            }
        }
        agentLogAIService(
            runId: "post-fix",
            hypothesisId: "H7",
            location: "ServicesAIService.swift:streamResponse",
            message: "Using OpenRouter provider",
            data: ["foundationModelsAvailable": false, "hasOpenRouterKey": true]
        )
        return streamWithOpenRouter(message: message, context: context)
    }

    /// Returns quick keyword-driven reply suggestions without an extra API call.
    func suggestedReplies(for message: String, context: [String]) async -> [String] {
        let lower = message.lowercased()
        if lower.contains("fuel") || lower.contains("diesel") || lower.contains("gas") {
            return ["Best fuel prices nearby?", "IFTA tips?", "Fuel economy advice"]
        }
        if lower.contains("route") || lower.contains("road") || lower.contains("navigate") {
            return ["Avoid tolls?", "Truck route restrictions?", "Low bridge alerts?"]
        }
        if lower.contains("hos") || lower.contains("hours") || lower.contains("rest") || lower.contains("sleep") {
            return ["HOS rules summary", "Nearest rest area?", "34-hour restart rules"]
        }
        if lower.contains("scale") || lower.contains("weigh") || lower.contains("weight") {
            return ["State weight limits?", "PrePass tips", "Scale bypass stations"]
        }
        if lower.contains("maintenance") || lower.contains("tire") || lower.contains("engine") {
            return ["Pre-trip checklist", "Find a truck shop", "Common issue fixes"]
        }
        if lower.contains("weather") || lower.contains("storm") || lower.contains("ice") || lower.contains("snow") {
            return ["Safe driving in bad weather?", "Road closures near me?", "Chain requirements?"]
        }
        return []
    }

    // MARK: - Foundation Models (on-device, iOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func streamWithFoundationModels(
        message: String,
        context: [String]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let session = LanguageModelSession(instructions: systemPrompt)

                    let recentContext = context.suffix(8).joined(separator: "\n")
                    let prompt = recentContext.isEmpty
                        ? message
                        : "\(recentContext)\n\nUser: \(message)"

                    var previousLength = 0
                    for try await snapshot in session.streamResponse(to: prompt) {
                        let current = snapshot.content
                        let newPart = String(current.dropFirst(previousLength))
                        previousLength = current.count
                        if !newPart.isEmpty {
                            continuation.yield(newPart)
                        }
                    }
                    continuation.finish()
                } catch {
                    do {
                        for try await chunk in streamWithOpenRouter(message: message, context: context) {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
    #endif

    // MARK: - OpenRouter (cloud fallback)

    private func streamWithOpenRouter(
        message: String,
        context: [String]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard !apiKey.isEmpty else {
                    continuation.finish(throwing: AIError.missingAPIKey)
                    return
                }

                do {
                    // Build OpenAI-compatible messages array
                    var messages: [[String: String]] = [
                        ["role": "system", "content": systemPrompt]
                    ]
                    for (i, ctx) in context.suffix(8).enumerated() {
                        messages.append(["role": i % 2 == 0 ? "user" : "assistant", "content": ctx])
                    }
                    messages.append(["role": "user", "content": message])

                    let body: [String: Any] = [
                        "model": openRouterModel,
                        "messages": messages,
                        "stream": true,
                        "max_tokens": 512,
                        "temperature": 0.7
                    ]

                    var request = URLRequest(url: openRouterURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Trucker Easy App", forHTTPHeaderField: "X-Title")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw AIError.apiError("HTTP \(code)")
                    }

                    // Parse Server-Sent Events stream
                    for try await line in asyncBytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }

                        guard
                            let data = payload.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                            let choices = json["choices"] as? [[String: Any]],
                            let delta = choices.first?["delta"] as? [String: Any],
                            let content = delta["content"] as? String
                        else { continue }

                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

}

// MARK: - Errors

enum AIError: LocalizedError {
    case missingAPIKey
    case serviceUnavailable(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key not configured in Info.plist."
        case .serviceUnavailable(let msg):
            return msg
        case .apiError(let msg):
            return "AI service error: \(msg)"
        }
    }
}
