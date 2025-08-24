import SwiftUI
import Combine

@MainActor
class DiscoverViewModel: ObservableObject {
    @Published var featuredContent: [DiscoverItem] = []
    @Published var categories: [DiscoverCategory] = []
    @Published var recentUpdates: [RegulationUpdate] = []
    @Published var isLoading = false
    @Published var error: DiscoverError?
    @Published var showingError = false
    @Published var searchQuery = ""
    @Published var selectedCategory: DiscoverCategory?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadDiscoverContent()
        setupSearch()
    }
    
    private func setupSearch() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.performSearch(query)
            }
            .store(in: &cancellables)
    }
    
    func loadDiscoverContent() {
        isLoading = true
        error = nil
        
        Task {
            do {
                async let featuredTask = loadFeaturedContent()
                async let categoriesTask = loadCategories()
                async let updatesTask = loadRecentUpdates()
                
                let (featured, categories, updates) = try await (featuredTask, categoriesTask, updatesTask)
                
                await MainActor.run {
                    self.featuredContent = featured
                    self.categories = categories
                    self.recentUpdates = updates
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.error = .loadingFailed(error.localizedDescription)
                    self.showingError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadFeaturedContent() async throws -> [DiscoverItem] {
        // Simulate API call - in production this would fetch from backend
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        return [
            DiscoverItem(
                id: UUID(),
                title: "New SOLAS Amendments 2024",
                subtitle: "Latest safety requirements for maritime vessels",
                imageURL: nil,
                contentType: .regulatory,
                category: .safety,
                isNew: true,
                publishedAt: Date().addingTimeInterval(-86400) // 1 day ago
            ),
            DiscoverItem(
                id: UUID(),
                title: "OSV Manning Requirements Update",
                subtitle: "Changes to crew certification for offshore vessels",
                imageURL: nil,
                contentType: .guidance,
                category: .manning,
                isNew: true,
                publishedAt: Date().addingTimeInterval(-172800) // 2 days ago
            ),
            DiscoverItem(
                id: UUID(),
                title: "Fire Safety Compliance Guide",
                subtitle: "Step-by-step guide for 46 CFR fire detection systems",
                imageURL: nil,
                contentType: .guide,
                category: .safety,
                isNew: false,
                publishedAt: Date().addingTimeInterval(-604800) // 1 week ago
            )
        ]
    }
    
    private func loadCategories() async throws -> [DiscoverCategory] {
        return DiscoverCategory.allCases
    }
    
    private func loadRecentUpdates() async throws -> [RegulationUpdate] {
        // Simulate API call
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        return [
            RegulationUpdate(
                id: UUID(),
                regulation: "46 CFR 109.213",
                title: "Fire detection systems - OSV requirements",
                changeType: .amended,
                effectiveDate: Date().addingTimeInterval(2592000), // 30 days from now
                summary: "Updated requirements for automatic fire detection in machinery spaces"
            ),
            RegulationUpdate(
                id: UUID(),
                regulation: "33 CFR 151.10",
                title: "Oil pollution prevention regulations",
                changeType: .clarification,
                effectiveDate: Date().addingTimeInterval(-86400), // Yesterday
                summary: "Clarification on discharge monitoring requirements"
            ),
            RegulationUpdate(
                id: UUID(),
                regulation: "46 CFR 199.175",
                title: "Life-saving equipment requirements",
                changeType: .new,
                effectiveDate: Date().addingTimeInterval(5184000), // 60 days from now
                summary: "New requirements for emergency equipment on vessels over 300 GT"
            )
        ]
    }
    
    private func performSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Reset to original content when search is empty
            return
        }
        
        // Filter content based on search query
        _ = featuredContent.filter { item in
            item.title.localizedCaseInsensitiveContains(query) ||
            item.subtitle.localizedCaseInsensitiveContains(query)
        }
        
        // In a real app, this would trigger a search API call
        // For now, we just filter existing content
    }
    
    func selectCategory(_ category: DiscoverCategory?) {
        selectedCategory = category
        
        if let category = category {
            // Filter content by category
            _ = featuredContent.filter { $0.category == category }
            // Update UI with filtered content
        } else {
            // Show all content
        }
    }
    
    func refreshContent() {
        loadDiscoverContent()
    }
}

// MARK: - Supporting Models

struct DiscoverItem: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let imageURL: URL?
    let contentType: ContentType
    let category: DiscoverCategory
    let isNew: Bool
    let publishedAt: Date
    
    enum ContentType: String, CaseIterable {
        case regulatory = "regulatory"
        case guidance = "guidance"
        case guide = "guide"
        case news = "news"
        case update = "update"
        
        var displayName: String {
            switch self {
            case .regulatory: return "Regulatory"
            case .guidance: return "Guidance"
            case .guide: return "Guide"
            case .news: return "News"
            case .update: return "Update"
            }
        }
        
        var icon: String {
            switch self {
            case .regulatory: return "doc.text"
            case .guidance: return "lightbulb"
            case .guide: return "book"
            case .news: return "newspaper"
            case .update: return "arrow.triangle.2.circlepath"
            }
        }
    }
}

enum DiscoverCategory: String, CaseIterable {
    case safety = "safety"
    case manning = "manning"
    case environmental = "environmental"
    case navigation = "navigation"
    case construction = "construction"
    case equipment = "equipment"
    case operations = "operations"
    
    var displayName: String {
        switch self {
        case .safety: return "Safety"
        case .manning: return "Manning"
        case .environmental: return "Environmental"
        case .navigation: return "Navigation"
        case .construction: return "Construction"
        case .equipment: return "Equipment"
        case .operations: return "Operations"
        }
    }
    
    var icon: String {
        switch self {
        case .safety: return "shield.checkered"
        case .manning: return "person.3"
        case .environmental: return "leaf"
        case .navigation: return "location"
        case .construction: return "hammer"
        case .equipment: return "gear"
        case .operations: return "slider.horizontal.3"
        }
    }
    
    var color: Color {
        switch self {
        case .safety: return .red
        case .manning: return .blue
        case .environmental: return .green
        case .navigation: return .purple
        case .construction: return .orange
        case .equipment: return .gray
        case .operations: return .indigo
        }
    }
}

struct RegulationUpdate: Identifiable {
    let id: UUID
    let regulation: String
    let title: String
    let changeType: ChangeType
    let effectiveDate: Date
    let summary: String
    
    enum ChangeType: String, CaseIterable {
        case new = "new"
        case amended = "amended"
        case repealed = "repealed"
        case clarification = "clarification"
        
        var displayName: String {
            switch self {
            case .new: return "New"
            case .amended: return "Amended"
            case .repealed: return "Repealed"
            case .clarification: return "Clarification"
            }
        }
        
        var color: Color {
            switch self {
            case .new: return .green
            case .amended: return .blue
            case .repealed: return .red
            case .clarification: return .orange
            }
        }
    }
}

enum DiscoverError: Error, LocalizedError {
    case loadingFailed(String)
    case networkError
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .loadingFailed(let message):
            return "Failed to load content: \(message)"
        case .networkError:
            return "Network connection error"
        case .unauthorized:
            return "You don't have permission to access this content"
        }
    }
}