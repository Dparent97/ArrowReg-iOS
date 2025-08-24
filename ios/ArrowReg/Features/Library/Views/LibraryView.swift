import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = SavedQueriesViewModel()
    @State private var showingNewQuery = false
    @State private var selectedTab = 0
    @State private var bookmarkedSearches: [SearchResult] = []
    @State private var bookmarkedArticles: [BookmarkedArticle] = []
    // BookmarkService temporarily removed until properly added to target
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Content", selection: $selectedTab) {
                    Text("Saved Queries").tag(0)
                    Text("Bookmarked Searches").tag(1)
                    Text("Bookmarked Articles").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case 0:
                        if viewModel.savedQueries.isEmpty && !viewModel.isLoading {
                            emptyStateView
                        } else {
                            savedQueriesContent
                        }
                    case 1:
                        bookmarkedSearchesContent
                    case 2:
                        bookmarkedArticlesContent
                    default:
                        emptyStateView
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingNewQuery = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewQuery) {
                NewSavedQueryView { query in
                    viewModel.addSavedQuery(query)
                }
            }
            .refreshable {
                await loadAllContent()
            }
            .task {
                await loadAllContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SearchBookmarked"))) { _ in
                // Load from UserDefaults temporarily
                DispatchQueue.main.async {
                    print("📚 LibraryView: Received SearchBookmarked notification")
                    if let dataArray = UserDefaults.standard.array(forKey: "BookmarkedSearches") as? [Data] {
                        print("📚 LibraryView: Found \(dataArray.count) bookmarked items in UserDefaults")
                        bookmarkedSearches = dataArray.compactMap { data in
                            do {
                                return try JSONDecoder().decode(SearchResult.self, from: data)
                            } catch {
                                print("📚 LibraryView: Failed to decode bookmark: \(error)")
                                return nil
                            }
                        }
                        print("📚 LibraryView: Successfully decoded \(bookmarkedSearches.count) search results")
                    } else {
                        print("📚 LibraryView: No bookmarked searches found in UserDefaults")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ArticleBookmarked"))) { _ in
                // Load from UserDefaults temporarily
                if let dataArray = UserDefaults.standard.array(forKey: "BookmarkedArticles") as? [Data] {
                    bookmarkedArticles = dataArray.compactMap { try? JSONDecoder().decode(BookmarkedArticle.self, from: $0) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SearchBookmarkRemoved"))) { _ in
                // Reload bookmarks when one is removed - ensure main thread
                DispatchQueue.main.async {
                    print("📚 LibraryView: Received SearchBookmarkRemoved notification")
                    if let dataArray = UserDefaults.standard.array(forKey: "BookmarkedSearches") as? [Data] {
                        bookmarkedSearches = dataArray.compactMap { data in
                            do {
                                return try JSONDecoder().decode(SearchResult.self, from: data)
                            } catch {
                                print("❌ LibraryView: Failed to decode bookmark after removal: \\(error)")
                                return nil
                            }
                        }
                        print("📚 LibraryView: Updated to \\(bookmarkedSearches.count) bookmarked searches after removal")
                    }
                }
            }
        }
    }
    
    private var savedQueriesContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if viewModel.isLoading {
                    loadingView
                } else {
                    ForEach(viewModel.savedQueries) { query in
                        NavigationLink(destination: SavedQueryDetailView(query: query)) {
                            SavedQueryCard(query: query) {
                                viewModel.deleteSavedQuery(query)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding()
        }
    }
    
    private var bookmarkedSearchesContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if bookmarkedSearches.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bookmark.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No bookmarked searches yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Bookmark search results to save them here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(bookmarkedSearches) { result in
                        BookmarkedSearchCard(result: result, onDelete: {
                            deleteBookmark(result)
                        }, onViewResult: {
                            viewSearchResult(result)
                        })
                    }
                }
            }
            .padding()
        }
    }
    
    private var bookmarkedArticlesContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if bookmarkedArticles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "newspaper.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No bookmarked articles yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Bookmark news articles to save them here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(bookmarkedArticles) { article in
                        BookmarkedArticleCard(article: article)
                    }
                }
            }
            .padding()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                SavedQueryCardSkeleton()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Your Library")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Save frequently used searches and track regulation changes over time")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showingNewQuery = true }) {
                Label("Create Saved Query", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
        }
        .padding(.top, 60)
    }
    
    private func loadAllContent() async {
        await viewModel.loadSavedQueries()
        // Load from UserDefaults temporarily
        await MainActor.run {
            print("📚 LibraryView: Loading all content...")
            if let searchDataArray = UserDefaults.standard.array(forKey: "BookmarkedSearches") as? [Data] {
                print("📚 LibraryView: Found \(searchDataArray.count) bookmarked search items on load")
                bookmarkedSearches = searchDataArray.compactMap { data in
                do {
                    return try JSONDecoder().decode(SearchResult.self, from: data)
                } catch {
                    print("📚 LibraryView: Failed to decode bookmark on load: \(error)")
                    return nil
                }
            }
            print("📚 LibraryView: Loaded \(bookmarkedSearches.count) bookmarked searches")
            } else {
                print("📚 LibraryView: No bookmarked searches found on load")
            }
            if let articleDataArray = UserDefaults.standard.array(forKey: "BookmarkedArticles") as? [Data] {
                bookmarkedArticles = articleDataArray.compactMap { try? JSONDecoder().decode(BookmarkedArticle.self, from: $0) }
            }
        }
    }
    
    private func deleteBookmark(_ result: SearchResult) {
        // Remove from UserDefaults
        guard var dataArray = UserDefaults.standard.array(forKey: "BookmarkedSearches") as? [Data] else { return }
        
        dataArray = dataArray.filter { data in
            guard let bookmark = try? JSONDecoder().decode(SearchResult.self, from: data) else { return true }
            return bookmark.id != result.id
        }
        
        UserDefaults.standard.set(dataArray, forKey: "BookmarkedSearches")
        
        // Update local state on main thread
        DispatchQueue.main.async {
            bookmarkedSearches.removeAll { $0.id == result.id }
        }
        
        print("🗑️ Deleted bookmark: \\(result.query)")
    }
    
    private func viewSearchResult(_ result: SearchResult) {
        // Copy query to clipboard for now - in production this would navigate to Search tab
        UIPasteboard.general.string = result.query
        print("📋 Copied query to clipboard: \\(result.query)")
        // TODO: Navigate to Search tab and populate with this query
    }
}

// MARK: - Bookmarked Article Model
struct BookmarkedArticle: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let url: String
    let date: Date

    init(id: String, title: String, summary: String, source: String, url: String, date: Date) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.url = url
        self.date = date
    }

    init(article: NewsArticle) {
        self.init(id: article.id, title: article.title, summary: article.summary, source: article.source, url: article.url, date: article.publishedAt)
    }
}

// MARK: - Bookmarked Cards
struct BookmarkedSearchCard: View {
    let result: SearchResult
    let onDelete: () -> Void
    let onViewResult: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.query)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Text(result.answer)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            HStack {
                Text("Confidence: \(result.confidence)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: onViewResult) {
                    Text("View Result")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct BookmarkedArticleCard: View {
    let article: BookmarkedArticle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(article.title)
                .font(.headline)
                .lineLimit(2)
            
            Text(article.summary)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            HStack {
                Text(article.source)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let url = URL(string: article.url) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Library ViewModel

@MainActor
class SavedQueriesViewModel: ObservableObject {
    @Published var savedQueries: [SavedQuery] = []
    @Published var isLoading = false
    
    func loadSavedQueries() async {
        isLoading = true
        
        // Load from UserDefaults - production ready
        if let data = UserDefaults.standard.data(forKey: "SavedQueries"),
           let queries = try? JSONDecoder().decode([SavedQuery].self, from: data) {
            savedQueries = queries
            print("📚 Loaded \\(queries.count) saved queries from UserDefaults")
        } else {
            // No saved queries found - start with empty array
            savedQueries = []
            print("📚 No saved queries found - starting fresh")
        }
        
        isLoading = false
    }
    
    func clearAllSavedQueries() {
        savedQueries = []
        UserDefaults.standard.removeObject(forKey: "SavedQueries")
        print("🗑️ Cleared all saved queries")
    }
    
    func addSavedQuery(_ query: SavedQuery) {
        savedQueries.insert(query, at: 0)
        saveToPersistence()
    }
    
    func deleteSavedQuery(_ query: SavedQuery) {
        savedQueries.removeAll { $0.id == query.id }
        saveToPersistence()
    }
    
    private func saveToPersistence() {
        do {
            let data = try JSONEncoder().encode(savedQueries)
            UserDefaults.standard.set(data, forKey: "SavedQueries")
            print("💾 Saved \\(savedQueries.count) queries to UserDefaults")
        } catch {
            print("❌ Failed to save queries: \\(error)")
        }
    }
}

// MARK: - Supporting Models

struct SavedQuery: Identifiable, Codable {
    let id: UUID
    let title: String
    let query: String
    let mode: SearchMode
    let createdAt: Date
    var lastRunAt: Date?
    var snapshot: [SnapshotItem]?
    
    init(id: UUID = UUID(), title: String, query: String, mode: SearchMode = .qa, createdAt: Date = Date(), lastRunAt: Date? = nil, snapshot: [SnapshotItem]? = nil) {
        self.id = id
        self.title = title
        self.query = query
        self.mode = mode
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.snapshot = snapshot
    }
    
    var lastRunTimeAgo: String {
        guard let lastRunAt = lastRunAt else { return "Never run" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last run \(formatter.localizedString(for: lastRunAt, relativeTo: Date()))"
    }
}

struct SnapshotItem: Identifiable, Codable {
    let id = UUID()
    let regulation: String
    let title: String
    let summary: String
}

// MARK: - Supporting Views

struct SavedQueryCard: View {
    let query: SavedQuery
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(query.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(query.mode.displayName)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Menu {
                    Button("Run Query", systemImage: "play") {
                        // Run the saved query
                        print("Running query: \(query.query)")
                    }
                    
                    Button("Edit", systemImage: "pencil") {
                        // Edit query
                        print("Editing query")
                    }
                    
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            
            // Query preview
            Text(query.query)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            // Snapshot summary
            if let snapshot = query.snapshot, !snapshot.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(snapshot.count) regulation\(snapshot.count == 1 ? "" : "s") found")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(snapshot.prefix(2)) { item in
                        HStack {
                            Text(item.regulation)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                            
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(item.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    if snapshot.count > 2 {
                        Text("and \(snapshot.count - 2) more...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            
            // Footer
            Text(query.lastRunTimeAgo)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct SavedQueryCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(height: 20)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(width: 80, height: 16)
                }
                
                Spacer()
                
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 18, height: 18)
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemBackground))
                .frame(height: 40)
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemBackground))
                .frame(height: 12)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .redacted(reason: .placeholder)
    }
}

// MARK: - Detail Views

struct SavedQueryDetailView: View {
    let query: SavedQuery
    @State private var isRunning = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Query info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Query")
                        .font(.headline)
                    
                    Text(query.query)
                        .font(.body)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
                
                // Run button
                Button(action: {
                    isRunning = true
                    // Simulate running query
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isRunning = false
                    }
                }) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        
                        Text(isRunning ? "Running Query..." : "Run Query")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isRunning)
                
                // Last results
                if let snapshot = query.snapshot, !snapshot.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last Results")
                            .font(.headline)
                        
                        ForEach(snapshot) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.regulation)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                                
                                Text(item.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(item.summary)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle(query.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewSavedQueryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var query = ""
    @State private var selectedMode = SearchMode.qa
    
    let onSave: (SavedQuery) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Query Details") {
                    TextField("Title", text: $title)
                    TextField("Query", text: $query, axis: .vertical)
                        .lineLimit(3...6)
                    
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(SearchMode.allCases, id: \.self) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                }
                
                Section {
                    Button("Save Query") {
                        let savedQuery = SavedQuery(
                            title: title.isEmpty ? "Untitled Query" : title,
                            query: query,
                            mode: selectedMode
                        )
                        onSave(savedQuery)
                        dismiss()
                    }
                    .disabled(query.isEmpty)
                }
            }
            .navigationTitle("New Saved Query")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LibraryView()
}
