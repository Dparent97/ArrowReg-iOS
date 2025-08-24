import Foundation
import Combine

// MARK: - Backend Response Models
struct BackendSearchResponse: Codable {
    let ok: Bool
    let mode: String
    let query: String
    let answer: String
    let citations: [Citation]?
    let isWeatherRelated: Bool?
    let assistantId: String?
    let vectorStores: [String]?
    let threadId: String?
}

// MARK: - Stream Response Models
struct StreamResponse: Codable {
    let type: String
    let data: AnyCodable
    
    enum CodingKeys: String, CodingKey {
        case type, data
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else {
            value = ()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else {
            try container.encodeNil()
        }
    }
}

extension AnyCodable {
    static func ~= (lhs: String?, rhs: AnyCodable) -> String? {
        return rhs.value as? String
    }
    
    static func ~= (lhs: Int?, rhs: AnyCodable) -> Int? {
        return rhs.value as? Int
    }
    
    static func ~= (lhs: [String: Any]?, rhs: AnyCodable) -> [String: Any]? {
        return rhs.value as? [String: Any]
    }
}

class SearchService: ObservableObject {
    static let shared = SearchService()
    
    // Database mode toggle
    @Published var isOnlineMode = true // Default to online mode
    
    // Thread management for follow-up questions
    @Published var currentThreadId: String? = nil
    
    // Search history and suggestions
    @Published var searchHistory: [String] = []
    @Published var suggestions: [String] = []
    private let maxHistoryItems = 20
    
    private let localBaseURL = "http://localhost:8787"
    private let onlineBaseURL = "https://arrowreg-api.c8nr5ngjrz.workers.dev"
    private var baseURL: String { isOnlineMode ? onlineBaseURL : localBaseURL }
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    init() {
        // Load saved preference - default to online mode
        if UserDefaults.standard.object(forKey: "SearchServiceOnlineMode") == nil {
            isOnlineMode = true // Default to online
            UserDefaults.standard.set(true, forKey: "SearchServiceOnlineMode")
        } else {
            isOnlineMode = UserDefaults.standard.bool(forKey: "SearchServiceOnlineMode")
        }
        
        // Load search history
        if let savedHistory = UserDefaults.standard.array(forKey: "SearchHistory") as? [String] {
            searchHistory = savedHistory
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: config)
        
        // Setup date formatting
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(formatter)
        encoder.dateEncodingStrategy = .formatted(formatter)
    }
    
    func toggleDatabaseMode() {
        isOnlineMode.toggle()
        UserDefaults.standard.set(isOnlineMode, forKey: "SearchServiceOnlineMode")
        // Clear thread when switching modes
        currentThreadId = nil
    }
    
    func startNewConversation() {
        currentThreadId = nil
    }
    
    // MARK: - Search History Methods
    
    func saveToHistory(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        
        // Remove if already exists to avoid duplicates
        searchHistory.removeAll { $0 == trimmedQuery }
        
        // Insert at beginning
        searchHistory.insert(trimmedQuery, at: 0)
        
        // Limit to max items
        if searchHistory.count > maxHistoryItems {
            searchHistory = Array(searchHistory.prefix(maxHistoryItems))
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(searchHistory, forKey: "SearchHistory")
    }
    
    func getSuggestions(for query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return [] }
        
        return searchHistory.filter { 
            $0.lowercased().contains(trimmedQuery) && $0.lowercased() != trimmedQuery
        }.prefix(5).map { $0 }
    }
    
    func clearHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "SearchHistory")
    }

    func removeHistoryItem(at index: Int) {
        guard index < searchHistory.count else { return }
        searchHistory.remove(at: index)
        UserDefaults.standard.set(searchHistory, forKey: "SearchHistory")
    }

    // MARK: - Search Methods
    
    func search(_ request: SearchRequest) async throws -> SearchResult {
        // Save query to history
        saveToHistory(request.query)
        
        // Local mode: always return mock data
        if !isOnlineMode {
            return createMockSearchResult(for: request, isOffline: true)
        }
        
        // Create request with threadId if we have one
        var enhancedRequest = request
        if let threadId = currentThreadId {
            enhancedRequest.threadId = threadId
        }
        
        // Try hybrid search: online first, fallback to local
        return try await hybridSearch(enhancedRequest)
    }
    
    private func hybridSearch(_ request: SearchRequest) async throws -> SearchResult {
        do {
            // Try online search first
            return try await searchOnline(request)
        } catch {
            print("⚠️ Online search failed, falling back to local: \(error.localizedDescription)")
            // Fallback to local mock data
            return createMockSearchResult(for: request, isOffline: false, fallbackReason: "Online service unavailable")
        }
    }
    
    private func searchOnline(_ request: SearchRequest) async throws -> SearchResult {
        let url = URL(string: "\(baseURL)/api/search")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("*/*", forHTTPHeaderField: "Accept")
        
        // Add auth header if available
        if let authToken = getAuthToken() {
            urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        // Include threadId in the request payload
        var payload: [String: Any] = [
            "query": request.query,
            "mode": request.mode.rawValue
        ]
        
        if let threadId = request.threadId {
            payload["threadId"] = threadId
        }
        
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw SearchError.invalidQuery
        }
        
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SearchError.networkError
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                // Try to parse backend response, fallback to mock
                do {
                    let backendResponse = try JSONDecoder().decode(BackendSearchResponse.self, from: data)
                    
                    // Update current thread ID for follow-up questions
                    if let threadId = backendResponse.threadId {
                        await MainActor.run {
                            self.currentThreadId = threadId
                        }
                    }
                    
                    return SearchResult(
                        query: request.query,
                        answer: backendResponse.answer,
                        citations: backendResponse.citations ?? [],
                        confidence: 85,
                        isComplete: true,
                        isOffline: false
                    )
                } catch {
                    // Fallback to mock response
                    return createMockSearchResult(for: request, isOffline: false)
                }
                
            case 401:
                throw SearchError.unauthorized
            case 429:
                throw SearchError.rateLimited
            case 408:
                throw SearchError.timeout
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SearchError.serverError(errorMessage)
            }
            
        } catch let error as SearchError {
            throw error
        } catch {
            // If network fails in online mode, fallback to mock data
            return createMockSearchResult(for: request, isOffline: false)
        }
    }
    
    func searchFollowUp(_ request: SearchRequest) async throws -> SearchResult {
        saveToHistory(request.query)

        // Local mode: not supported for follow-ups
        if !isOnlineMode {
            throw SearchError.serverError("Follow-up questions require Online mode")
        }
        
        // Must have a current thread
        guard let threadId = currentThreadId else {
            throw SearchError.serverError("No active conversation thread")
        }
        
        // Online mode: use follow-up endpoint
        let url = URL(string: "\(baseURL)/api/search/followup")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("*/*", forHTTPHeaderField: "Accept")
        
        // Add auth header if available
        if let authToken = getAuthToken() {
            urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        // Create follow-up request payload
        let followUpPayload: [String: String] = [
            "query": request.query,
            "threadId": threadId,
            "mode": request.mode.rawValue
        ]
        
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: followUpPayload)
        } catch {
            throw SearchError.invalidQuery
        }
        
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SearchError.networkError
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                // Parse follow-up response
                do {
                    let backendResponse = try JSONDecoder().decode(BackendSearchResponse.self, from: data)
                    
                    return SearchResult(
                        query: request.query,
                        answer: backendResponse.answer,
                        citations: backendResponse.citations ?? [],
                        confidence: 85,
                        isComplete: true,
                        isOffline: false
                    )
                } catch {
                    throw SearchError.serverError("Failed to parse follow-up response")
                }
                
            case 401:
                throw SearchError.unauthorized
            case 429:
                throw SearchError.rateLimited
            case 408:
                throw SearchError.timeout
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SearchError.serverError(errorMessage)
            }
            
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.networkError
        }
    }
    
    func streamSearch(_ request: SearchRequest) -> AsyncThrowingStream<SearchChunk, Error> {
        saveToHistory(request.query)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Use real OpenAI streaming if available
                    if await isOpenAIAvailable() {
                        try await performOpenAIStreamSearch(request, continuation: continuation)
                    } else {
                        // Fallback to mock streaming
                        try await performMockStreamSearch(request, continuation: continuation)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func performOpenAIStreamSearch(_ request: SearchRequest, continuation: AsyncThrowingStream<SearchChunk, Error>.Continuation) async throws {
        let url = URL(string: "\(baseURL)/api/search/stream")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        if let authToken = getAuthToken() {
            urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw SearchError.invalidQuery
        }
        
        let (asyncBytes, response) = try await session.bytes(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SearchError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        // Process Server-Sent Events
        var buffer = ""
        var byteBuffer = Data()
        
        for try await byte in asyncBytes {
            // Accumulate bytes and process as UTF-8 when we have complete characters
            byteBuffer.append(byte)
            
            // Try to convert accumulated bytes to string
            if let partialString = String(data: byteBuffer, encoding: .utf8) {
                buffer += partialString
                byteBuffer.removeAll()
            } else if byteBuffer.count > 4 {
                // If we have more than 4 bytes and still can't decode, skip the first byte
                // (UTF-8 characters are at most 4 bytes)
                byteBuffer.removeFirst()
            }
            
            // Process complete lines
            while let lineEnd = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...lineEnd)
                
                // Skip empty lines and comments
                if line.isEmpty || line.hasPrefix(":") {
                    continue
                }
                
                // Parse SSE data line
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    // Handle special cases
                    if jsonString == "\"stream_end\"" || jsonString.contains("stream_end") {
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }
                    
                    // Parse JSON data
                    if let data = jsonString.data(using: .utf8) {
                        do {
                            let streamResponse = try JSONDecoder().decode(StreamResponse.self, from: data)
                            
                            switch streamResponse.type {
                            case "content":
                                if let content = streamResponse.data.value as? String {
                                    continuation.yield(.content(content))
                                }
                                
                            case "citation":
                                if let citationData = streamResponse.data.value as? [String: Any],
                                   let citation = parseCitation(from: citationData) {
                                    continuation.yield(.citation(citation))
                                }
                                
                            case "confidence":
                                if let confidence = streamResponse.data.value as? Int {
                                    continuation.yield(.confidence(confidence))
                                }
                                
                            case "done":
                                continuation.yield(.done)
                                continuation.finish()
                                return
                                
                            case "error":
                                if let errorMessage = streamResponse.data.value as? String {
                                    continuation.yield(.error(errorMessage))
                                }
                                continuation.finish()
                                return
                                
                            default:
                                // Unknown type, ignore
                                break
                            }
                            
                        } catch {
                            Logger.network.error("Failed to parse stream response: \(error)")
                        }
                    }
                }
            }
        }
        
        // Stream ended without explicit completion
        continuation.yield(.done)
        continuation.finish()
    }
    
    private func performMockStreamSearch(_ request: SearchRequest, continuation: AsyncThrowingStream<SearchChunk, Error>.Continuation) async throws {
        let result = try await search(request)
        
        // Simulate streaming by breaking up the response
        let words = result.answer.components(separatedBy: " ")
        let chunkSize = 5
        
        for i in stride(from: 0, to: words.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, words.count)
            let chunk = Array(words[i..<endIndex]).joined(separator: " ")
            
            continuation.yield(.content(chunk + " "))
            
            // Small delay to simulate streaming
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Send citations
        for citation in result.citations {
            continuation.yield(.citation(citation))
        }
        
        continuation.yield(.confidence(result.confidence))
        continuation.yield(.done)
        continuation.finish()
    }
    
    private func isOpenAIAvailable() async -> Bool {
        // In Online mode, try to use OpenAI features (but streaming is disabled for now)
        // In Local mode, always use mock data
        if !isOnlineMode {
            return false // Local mode always uses mock data
        }
        
        // Online mode: disable streaming for now since /api/search/stream endpoint is not available
        // The backend only supports /api/search endpoint currently
        return false
    }
    
    private func parseCitation(from data: [String: Any]) -> Citation? {
        guard let source = data["source"] as? String,
              let section = data["section"] as? String,
              let title = data["title"] as? String else {
            return nil
        }
        
        let relevanceScore = data["relevanceScore"] as? Double ?? 0.5
        
        // Determine regulation source enum
        let regulationSource: RegulationSource
        if source.contains("CFR Title 33") {
            regulationSource = .cfr33
        } else if source.contains("CFR Title 46") {
            regulationSource = .cfr46
        } else if source.contains("ABS") {
            regulationSource = .abs
        } else {
            regulationSource = .nvic
        }
        
        return Citation(
            title: title,
            section: section,
            source: regulationSource,
            url: data["url"] as? String,
            relevanceScore: relevanceScore
        )
    }
    
    // MARK: - Health Check
    
    func healthCheck() async throws -> Bool {
        let url = URL(string: "\(baseURL)/health")!
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return status == "healthy"
            }
            
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func getAuthToken() -> String? {
        // TODO: Implement secure token storage/retrieval
        return nil
    }
    
    private func createMockSearchResult(for request: SearchRequest, isOffline: Bool = false, fallbackReason: String? = nil) -> SearchResult {
        let mockAnswers = [
            "fire": "Fire detection systems on OSVs are required under 46 CFR 109.213. These systems must include automatic detection in machinery spaces, accommodation areas, and other enclosed spaces as specified in the regulations.",
            "life": "Life-saving equipment requirements are detailed in 46 CFR 199. This includes life rafts, life jackets, immersion suits, and emergency equipment based on vessel type and route.",
            "oil": "Oil discharge regulations are covered under 33 CFR 151. Vessels must have approved oil discharge monitoring and control systems, with strict limits on overboard discharges.",
            "manning": "Manning requirements vary by vessel type and route, as specified in 46 CFR Chapter I. OSVs typically require licensed officers and certificated crew members based on gross tonnage and service."
        ]
        
        let query = request.query.lowercased()
        var answer = "I found information related to your query about maritime regulations."
        
        // Simple keyword matching for demo
        for (keyword, response) in mockAnswers {
            if query.contains(keyword) {
                answer = response
                break
            }
        }
        
        // Add fallback reason if provided
        if let fallbackReason = fallbackReason {
            answer = "⚠️ \(fallbackReason). \(answer)"
        }
        
        let citations = [
            Citation(
                title: "Offshore Supply Vessels",
                section: "46 CFR 109.213",
                source: .cfr46,
                url: "https://www.ecfr.gov/current/title-46/chapter-I/subchapter-I/part-109/section-109.213",
                relevanceScore: 0.95
            ),
            Citation(
                title: "Oil Pollution Prevention",
                section: "33 CFR 151.10",
                source: .cfr33,
                url: "https://www.ecfr.gov/current/title-33/chapter-I/subchapter-O/part-151",
                relevanceScore: 0.87
            )
        ]
        
        return SearchResult(
            query: request.query,
            answer: answer,
            citations: citations,
            confidence: 92,
            isComplete: true,
            isOffline: isOffline
        )
    }
}