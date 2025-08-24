import Foundation

// MARK: - Citation Models
struct CitationSource {
    let label: String
    let title: String
    let url: String?
    let filename: String?
}

struct SearchResponse {
    let content: String
    let sources: [CitationSource]
    let threadID: String?
    let timestamp: Date = Date()
}

// MARK: - Search Request Models
struct SearchRequest: Codable {
    let query: String
    let mode: SearchMode
    let filters: SearchFilters
    let maxResults: Int
    var threadId: String? = nil  // Add this for conversation continuity
    
    init(query: String, mode: SearchMode = .qa, filters: SearchFilters = SearchFilters(), maxResults: Int = 10) {
        self.query = query
        self.mode = mode
        self.filters = filters
        self.maxResults = maxResults
    }
}

enum SearchMode: String, Codable, CaseIterable {
    case qa = "qa"
    case section = "section"
    case compare = "compare"
    
    var displayName: String {
        switch self {
        case .qa: return "Q&A Mode"
        case .section: return "Section Search"
        case .compare: return "Compare Mode"
        }
    }
    
    var description: String {
        switch self {
        case .qa: return "Get direct answers to your questions"
        case .section: return "Find specific regulation sections"
        case .compare: return "Compare regulations across sources"
        }
    }
}

struct SearchFilters: Codable {
    var sources: [RegulationSource]
    var includeNVIC: Bool
    var includeClass: Bool
    var dateRange: DateRange?
    var maxResults: Int
    
    init() {
        self.sources = [.cfr33, .cfr46]
        self.includeNVIC = false
        self.includeClass = false
        self.dateRange = nil
        self.maxResults = 10
    }
}

struct DateRange: Codable {
    let start: Date
    let end: Date
}

// MARK: - Search Response Models
struct SearchResult: Codable, Identifiable {
    let id: String
    var query: String // Add query property for bookmarking
    var answer: String
    var citations: [Citation]
    let confidence: Int
    let isComplete: Bool
    let isOffline: Bool
    let timestamp: Date
    
    // Custom decoding to handle legacy bookmarks without query field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? "Unknown Query"
        answer = try container.decode(String.self, forKey: .answer)
        citations = try container.decode([Citation].self, forKey: .citations)
        confidence = try container.decode(Int.self, forKey: .confidence)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        isOffline = try container.decode(Bool.self, forKey: .isOffline)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, query, answer, citations, confidence, isComplete, isOffline, timestamp
    }
    
    init(id: String = UUID().uuidString, query: String = "", answer: String = "", citations: [Citation] = [], confidence: Int = 0, isComplete: Bool = false, isOffline: Bool = false) {
        self.id = id
        self.query = query
        self.answer = answer
        self.citations = citations
        self.confidence = confidence
        self.isComplete = isComplete
        self.isOffline = isOffline
        self.timestamp = Date()
    }
}

struct Citation: Codable, Hashable {
    let id: String
    let title: String
    let section: String
    let source: RegulationSource
    let url: String?
    let relevanceScore: Double
    
    init(id: String = UUID().uuidString, title: String, section: String, source: RegulationSource, url: String? = nil, relevanceScore: Double = 0.0) {
        self.id = id
        self.title = title
        self.section = section
        self.source = source
        self.url = url
        self.relevanceScore = relevanceScore
    }
}

// MARK: - Streaming Response Models
enum SearchChunk {
    case content(String)
    case citation(Citation)
    case confidence(Int)
    case done
    case error(String)
}

// MARK: - Error Models
enum SearchError: Error, LocalizedError {
    case networkError
    case invalidQuery
    case serverError(String)
    case rateLimited
    case unauthorized
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error. Please check your internet connection."
        case .invalidQuery:
            return "Invalid search query. Please try a different search."
        case .serverError(let message):
            return "Server error: \(message)"
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .unauthorized:
            return "Authentication required. Please sign in."
        case .timeout:
            return "Request timed out. Please try again."
        }
    }
}