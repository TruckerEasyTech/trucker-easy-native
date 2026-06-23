import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif


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

    // Proxy SEGURO: a chave do OpenRouter fica no servidor (Edge Function `ai-proxy`); o app chama via
    // anon key. Se o proxy ainda não estiver publicado (503/404), cai na chamada direta (transição,
    // enquanto a OpenRouterAPIKey ainda existir no xcconfig). Remova a chave do xcconfig após o deploy.
    private var supabaseURL: String { (Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "").trimmingCharacters(in: .whitespaces) }
    private var supabaseAnonKey: String { (Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? "").trimmingCharacters(in: .whitespaces) }
    private var aiProxyURL: URL? {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else { return nil }
        let base = supabaseURL.hasSuffix("/") ? String(supabaseURL.dropLast()) : supabaseURL
        return URL(string: "\(base)/functions/v1/ai-proxy")
    }

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
        // Diz EXATAMENTE por que o modelo on-device não está disponível (acionável pro motorista).
        var onDeviceIssue = "No on-device model available"
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return streamWithFoundationModels(message: message, context: context)
            case .unavailable(.appleIntelligenceNotEnabled):
                onDeviceIssue = "Apple Intelligence is turned OFF — enable it in Settings → Apple Intelligence & Siri, then try again"
            case .unavailable(.modelNotReady):
                onDeviceIssue = "Apple Intelligence model is still downloading — try again in a few minutes"
            case .unavailable(.deviceNotEligible):
                onDeviceIssue = "This device does not support Apple Intelligence"
            case .unavailable:
                onDeviceIssue = "On-device model unavailable"
            }
        }
        #endif
        if apiKey.isEmpty {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AIError.serviceUnavailable(
                    "\(onDeviceIssue). Cloud fallback is also off (OpenRouterAPIKey missing)."
                ))
            }
        }
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
        // Snapshot da config AQUI (no contexto do método) → o Task concorrente abaixo usa só estes
        // locais, sem acessar propriedades do serviço. Isso elimina o erro de isolamento/concorrência
        // (Swift 6 / strict concurrency) ao ler aiProxyURL/supabaseAnonKey de dentro do Task.
        let proxyURL = aiProxyURL
        let anonKey = supabaseAnonKey
        let directKey = apiKey
        let directURL = openRouterURL
        let model = openRouterModel
        let sysPrompt = systemPrompt
        return AsyncThrowingStream { continuation in
            Task {
                guard proxyURL != nil || !directKey.isEmpty else {
                    continuation.finish(throwing: AIError.missingAPIKey)
                    return
                }

                do {
                    // Build OpenAI-compatible messages array
                    var messages: [[String: String]] = [
                        ["role": "system", "content": sysPrompt]
                    ]
                    for (i, ctx) in context.suffix(8).enumerated() {
                        messages.append(["role": i % 2 == 0 ? "user" : "assistant", "content": ctx])
                    }
                    messages.append(["role": "user", "content": message])

                    let body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true,
                        "max_tokens": 512,
                        "temperature": 0.7
                    ]

                    let bodyData = try JSONSerialization.data(withJSONObject: body)
                    var useProxy = (proxyURL != nil)
                    func makeRequest() -> URLRequest {
                        var request = URLRequest(url: useProxy ? proxyURL! : directURL)
                        request.httpMethod = "POST"
                        request.httpBody = bodyData
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("Trucker Easy App", forHTTPHeaderField: "X-Title")
                        if useProxy {
                            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
                            request.setValue(anonKey, forHTTPHeaderField: "apikey")
                        } else {
                            request.setValue("Bearer \(directKey)", forHTTPHeaderField: "Authorization")
                        }
                        return request
                    }

                    var (asyncBytes, response) = try await URLSession.shared.bytes(for: makeRequest())
                    var http = response as? HTTPURLResponse
                    // Proxy ainda não publicado (503/404) e há chave direta → fallback direto (transição).
                    if useProxy, let h = http, (h.statusCode == 503 || h.statusCode == 404), !directKey.isEmpty {
                        useProxy = false
                        (asyncBytes, response) = try await URLSession.shared.bytes(for: makeRequest())
                        http = response as? HTTPURLResponse
                    }
                    guard let finalHttp = http, (200...299).contains(finalHttp.statusCode) else {
                        throw AIError.apiError("HTTP \(http?.statusCode ?? 0)")
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
