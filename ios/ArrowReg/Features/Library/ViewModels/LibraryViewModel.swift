import SwiftUI
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var savedItems: [LibraryItem] = []
    @Published var collections: [LibraryCollection] = []
    @Published var recentlyViewed: [LibraryItem] = []
    @Published var isLoading = false
    @Published var error: LibraryError?
    @Published var showingError = false
    @Published var searchQuery = ""
    @Published var selectedFilter: LibraryFilter = .all
    @Published var sortOption: SortOption = .dateAdded
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadLibraryContent()
        setupSearch()
    }
    
    private func setupSearch() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.filterContent()
            }
            .store(in: &cancellables)
        
        Publishers.CombineLatest($selectedFilter, $sortOption)
            .sink { [weak self] _, _ in
                self?.filterContent()
            }
            .store(in: &cancellables)
    }
    
    func loadLibraryContent() {
        isLoading = true
        error = nil
        
        Task {
            do {
                async let savedItemsTask = loadSavedItems()
                async let collectionsTask = loadCollections()
                async let recentTask = loadRecentlyViewed()
                
                let (saved, collections, recent) = try await (savedItemsTask, collectionsTask, recentTask)
                
                await MainActor.run {
                    self.savedItems = saved
                    self.collections = collections
                    self.recentlyViewed = recent
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
    
    private func loadSavedItems() async throws -> [LibraryItem] {
        // Load from UserDefaults or Core Data in production
        if let data = userDefaults.data(forKey: "SavedLibraryItems"),
           let items = try? JSONDecoder().decode([LibraryItem].self, from: data) {
            return items
        }
        
        // Return sample data for now
        return [
            LibraryItem(
                id: UUID(),
                title: "Fire Detection Requirements - 46 CFR 109.213",
                subtitle: "Automatic detection systems for OSVs",
                type: .regulation,
                source: .cfr46,
                savedAt: Date().addingTimeInterval(-86400),
                tags: ["fire", "detection", "OSV", "safety"]
            ),
            LibraryItem(
                id: UUID(),
                title: "Manning Requirements for Supply Vessels",
                subtitle: "Certification and licensing requirements",
                type: .searchResult,
                source: .cfr46,
                savedAt: Date().addingTimeInterval(-172800),
                tags: ["manning", "certification", "supply vessel"]
            ),
            LibraryItem(
                id: UUID(),
                title: "Oil Discharge Regulations - 33 CFR 151",
                subtitle: "Prevention of oil pollution from vessels",
                type: .regulation,
                source: .cfr33,
                savedAt: Date().addingTimeInterval(-259200),
                tags: ["oil", "discharge", "pollution", "environmental"]
            )
        ]
    }
    
    private func loadCollections() async throws -> [LibraryCollection] {
        // Load user-created collections
        if let data = userDefaults.data(forKey: "LibraryCollections"),
           let collections = try? JSONDecoder().decode([LibraryCollection].self, from: data) {
            return collections
        }
        
        // Return default collections
        return [
            LibraryCollection(
                id: UUID(),
                name: "Fire Safety",
                description: "Fire detection and suppression regulations",
                itemCount: 12,
                createdAt: Date().addingTimeInterval(-604800)
            ),
            LibraryCollection(
                id: UUID(),
                name: "OSV Operations",
                description: "Offshore Supply Vessel specific regulations",
                itemCount: 8,
                createdAt: Date().addingTimeInterval(-1209600)
            ),
            LibraryCollection(
                id: UUID(),
                name: "Environmental Compliance",
                description: "Environmental protection and pollution prevention",
                itemCount: 15,
                createdAt: Date().addingTimeInterval(-1814400)
            )
        ]
    }
    
    private func loadRecentlyViewed() async throws -> [LibraryItem] {
        if let data = userDefaults.data(forKey: "RecentlyViewedItems"),
           let items = try? JSONDecoder().decode([LibraryItem].self, from: data) {
            return Array(items.prefix(10)) // Keep only last 10
        }
        
        return []
    }
    
    private func filterContent() {
        var filtered = savedItems
        
        // Apply search filter
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = filtered.filter { item in
                item.title.localizedCaseInsensitiveContains(searchQuery) ||
                item.subtitle.localizedCaseInsensitiveContains(searchQuery) ||
                item.tags.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
            }
        }
        
        // Apply type filter
        switch selectedFilter {
        case .all:
            break
        case .regulations:
            filtered = filtered.filter { $0.type == .regulation }
        case .searchResults:
            filtered = filtered.filter { $0.type == .searchResult }
        case .guides:
            filtered = filtered.filter { $0.type == .guide }
        case .notes:
            filtered = filtered.filter { $0.type == .note }
        }
        
        // Apply sorting
        switch sortOption {
        case .dateAdded:
            filtered.sort(by: { $0.savedAt > $1.savedAt })
        case .title:
            filtered.sort(by: { $0.title < $1.title })
        case .source:
            filtered.sort(by: { $0.source.displayName < $1.source.displayName })
        }
        
        // Update filtered results would go here in production
    }
    
    func saveItem(_ item: LibraryItem) {
        guard !savedItems.contains(where: { $0.id == item.id }) else { return }
        
        savedItems.insert(item, at: 0)
        saveToPersistence()
    }
    
    func removeItem(_ item: LibraryItem) {
        savedItems.removeAll { $0.id == item.id }
        saveToPersistence()
    }
    
    func addToRecentlyViewed(_ item: LibraryItem) {
        // Remove if already exists
        recentlyViewed.removeAll { $0.id == item.id }
        
        // Add to beginning
        recentlyViewed.insert(item, at: 0)
        
        // Keep only last 10
        if recentlyViewed.count > 10 {
            recentlyViewed = Array(recentlyViewed.prefix(10))
        }
        
        saveRecentlyViewed()
    }
    
    func createCollection(name: String, description: String) {
        let collection = LibraryCollection(
            id: UUID(),
            name: name,
            description: description,
            itemCount: 0,
            createdAt: Date()
        )
        
        collections.append(collection)
        saveCollections()
    }
    
    func deleteCollection(_ collection: LibraryCollection) {
        collections.removeAll { $0.id == collection.id }
        saveCollections()
    }
    
    private func saveToPersistence() {
        do {
            let data = try JSONEncoder().encode(savedItems)
            userDefaults.set(data, forKey: "SavedLibraryItems")
        } catch {
            Logger.app.error("Failed to save library items: \(error)")
        }
    }
    
    private func saveRecentlyViewed() {
        do {
            let data = try JSONEncoder().encode(recentlyViewed)
            userDefaults.set(data, forKey: "RecentlyViewedItems")
        } catch {
            Logger.app.error("Failed to save recently viewed items: \(error)")
        }
    }
    
    private func saveCollections() {
        do {
            let data = try JSONEncoder().encode(collections)
            userDefaults.set(data, forKey: "LibraryCollections")
        } catch {
            Logger.app.error("Failed to save collections: \(error)")
        }
    }
}

// MARK: - Supporting Models

struct LibraryItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let subtitle: String
    let type: ItemType
    let source: RegulationSource
    let savedAt: Date
    let tags: [String]
    var notes: String?
    
    enum ItemType: String, CaseIterable, Codable {
        case regulation = "regulation"
        case searchResult = "searchResult"
        case guide = "guide"
        case note = "note"
        
        var displayName: String {
            switch self {
            case .regulation: return "Regulation"
            case .searchResult: return "Search Result"
            case .guide: return "Guide"
            case .note: return "Note"
            }
        }
        
        var icon: String {
            switch self {
            case .regulation: return "doc.text"
            case .searchResult: return "magnifyingglass"
            case .guide: return "book"
            case .note: return "note.text"
            }
        }
    }
}

struct LibraryCollection: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let itemCount: Int
    let createdAt: Date
}

enum LibraryFilter: String, CaseIterable {
    case all = "all"
    case regulations = "regulations"
    case searchResults = "searchResults"
    case guides = "guides"
    case notes = "notes"
    
    var displayName: String {
        switch self {
        case .all: return "All Items"
        case .regulations: return "Regulations"
        case .searchResults: return "Search Results"
        case .guides: return "Guides"
        case .notes: return "Notes"
        }
    }
}

enum SortOption: String, CaseIterable {
    case dateAdded = "dateAdded"
    case title = "title"
    case source = "source"
    
    var displayName: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .title: return "Title"
        case .source: return "Source"
        }
    }
}

enum LibraryError: Error, LocalizedError {
    case loadingFailed(String)
    case savingFailed(String)
    case itemNotFound
    
    var errorDescription: String? {
        switch self {
        case .loadingFailed(let message):
            return "Failed to load library: \(message)"
        case .savingFailed(let message):
            return "Failed to save: \(message)"
        case .itemNotFound:
            return "Item not found in library"
        }
    }
}