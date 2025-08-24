import SwiftUI
import Combine
import Foundation

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [SearchResult] = []
    @Published var isSearching = false
    @Published var filters = SearchFilters()
    @Published var recentSearches: [String] = []
    @Published var error: SearchError?
    @Published var showingError = false
    
    private let searchService: SearchService
    private let weatherService: WeatherService
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    
    let exampleQueries = [
        "What are fire detection requirements for OSVs?",
        "Manning requirements for supply vessels under 46 CFR",
        "Oil discharge regulations in 33 CFR 151",
        "Life-saving equipment requirements for offshore vessels",
        "Safety management system compliance",
        "Radio communication requirements for OSVs",
        "Weather routing procedures for rough seas",
        "Storm shelter requirements by vessel type"
    ]
    
    init(searchService: SearchService = SearchService.shared, weatherService: WeatherService = WeatherService.shared) {
        self.searchService = searchService
        self.weatherService = weatherService
        loadRecentSearches()
        setupSearchDebounce()
    }
    
    // MARK: - Search Actions

    func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        saveToRecentSearches(trimmedQuery)

        let request = SearchRequest(
            query: trimmedQuery,
            mode: .qa,
            filters: filters,
            maxResults: 10
        )

        executeSearch(request: request, followUp: false)
    }

    func performFollowUpSearch(_ followUpQuery: String) {
        guard !followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let trimmedQuery = followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        saveToRecentSearches(trimmedQuery)

        let request = SearchRequest(
            query: trimmedQuery,
            mode: .qa,
            filters: filters,
            maxResults: 10
        )

        executeSearch(request: request, followUp: true)
    }

    private func executeSearch(request: SearchRequest, followUp: Bool) {
        isSearching = true
        error = nil

        Task {
            do {
                let result: SearchResult
                if followUp {
                    result = try await searchService.searchFollowUp(request)
                } else {
                    result = try await searchService.search(request)
                }

                await MainActor.run {
                    if followUp {
                        self.results.append(result)
                    } else {
                        self.results = [result]
                    }
                    self.isSearching = false
                }

            } catch let searchError as SearchError {
                await MainActor.run {
                    self.error = searchError
                    self.showingError = true
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.error = .networkError
                    self.showingError = true
                    self.isSearching = false
                }
            }
        }
    }
    
    func performStreamingSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // Start a new conversation (clear thread)
        SearchService.shared.startNewConversation()
        
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        saveToRecentSearches(trimmedQuery)
        
        isSearching = true
        error = nil
        results = []
        
        Task { @MainActor in
            let request = SearchRequest(
                query: trimmedQuery,
                mode: .qa,
                filters: filters,
                maxResults: 10
            )
            
            var currentResult = SearchResult(query: trimmedQuery)
            
            do {
                let stream = searchService.streamSearch(request)

                for try await chunk in stream {
                    switch chunk {
                    case .content(let text):
                        currentResult.answer += text
                        self.results = [currentResult]

                    case .citation(let citation):
                        currentResult.citations.append(citation)

                    case .confidence(let confidence):
                        currentResult = SearchResult(
                            id: currentResult.id,
                            query: currentResult.query,
                            answer: currentResult.answer,
                            citations: currentResult.citations,
                            confidence: confidence,
                            isComplete: false
                        )
                        self.results = [currentResult]

                    case .done:
                        currentResult = SearchResult(
                            id: currentResult.id,
                            query: currentResult.query,
                            answer: currentResult.answer,
                            citations: currentResult.citations,
                            confidence: currentResult.confidence,
                            isComplete: true
                        )
                        self.results = [currentResult]
                        self.isSearching = false

                    case .error(let errorMessage):
                        self.error = .serverError(errorMessage)
                        self.showingError = true
                        self.isSearching = false
                    }
                }
                
            } catch let searchError as SearchError {
                self.error = searchError
                self.showingError = true
                self.isSearching = false
            } catch {
                self.error = .networkError
                self.showingError = true
                self.isSearching = false
            }
        }
    }
    
    func clearSearch() {
        searchQuery = ""
        results = []
        error = nil
        showingError = false
    }
    
    func selectExampleQuery(_ query: String) {
        searchQuery = query
        performStreamingSearch()
    }
    

    
    // MARK: - Filter Actions
    
    func toggleCFROnly() {
        if filters.sources == [.cfr33, .cfr46] {
            filters.sources = RegulationSource.allCases
        } else {
            filters.sources = [.cfr33, .cfr46]
        }
    }
    
    func toggleNVIC() {
        filters.includeNVIC.toggle()
    }
    
    func toggleClassRules() {
        filters.includeClass.toggle()
    }
    
    // MARK: - Private Methods
    
    private func setupSearchDebounce() {
        // Add debounced search if needed
        $searchQuery
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { _ in
                // Could trigger auto-suggestions here
            }
            .store(in: &cancellables)
    }
    
    private func saveToRecentSearches(_ query: String) {
        // Remove if already exists
        recentSearches.removeAll { $0 == query }
        
        // Add to beginning
        recentSearches.insert(query, at: 0)
        
        // Keep only last 10
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(recentSearches, forKey: "RecentSearches")
    }
    
    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "RecentSearches") ?? []
    }
    
    // MARK: - Bookmark Support
    
    func bookmarkResult(_ result: SearchResult) {
        // Save to UserDefaults temporarily until BookmarkService is properly added to target
        var existingBookmarks = UserDefaults.standard.array(forKey: "BookmarkedSearches") as? [Data] ?? []
        if let data = try? JSONEncoder().encode(result) {
            existingBookmarks.append(data)
            UserDefaults.standard.set(existingBookmarks, forKey: "BookmarkedSearches")
        }
        NotificationCenter.default.post(name: NSNotification.Name("SearchBookmarked"), object: result)
    }
    
    // MARK: - Debounced Search
    
    func performDebouncedSearch(_ query: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }

            searchQuery = query

            performStreamingSearch()
        }
    }
    
    func getSuggestions() -> [String] {
        return searchService.getSuggestions(for: searchQuery)
    }
}