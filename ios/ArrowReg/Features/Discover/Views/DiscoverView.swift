import SwiftUI

struct DiscoverView: View {
    @State private var articles: [NewsArticle] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if isLoading {
                        loadingView
                    } else if articles.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(articles) { article in
                            ArticleCard(article: article)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await loadArticles()
            }
            .task {
                await loadArticles()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<5, id: \.self) { _ in
                ArticleCardSkeleton()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Stay Updated")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Discover the latest maritime news, regulation updates, and industry insights")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 60)
    }
    
    private func loadArticles() async {
        isLoading = true
        
        do {
            // Fetch real news from backend
            let url = URL(string: "https://arrowreg-api.c8nr5ngjrz.workers.dev/api/news")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(NewsResponse.self, from: data)
            
            // Convert to our NewsArticle model
            articles = response.articles.map { article in
                NewsArticle(
                    id: article.id,
                    title: article.title,
                    summary: article.summary ?? "No summary available",
                    source: article.source,
                    publishedAt: ISO8601DateFormatter().date(from: article.publishedAt) ?? Date(),
                    category: categorizeArticle(article.title),
                    url: article.url
                )
            }
        } catch {
            // Fallback to mock data if API fails
            articles = [
                NewsArticle(
                    id: "1",
                    title: "New USCG Safety Management System Requirements",
                    summary: "The Coast Guard has updated SMS requirements for commercial vessels, with new compliance deadlines announced.",
                    source: "Maritime Executive",
                    publishedAt: Date().addingTimeInterval(-86400),
                    category: .regulation,
                    url: "https://maritime-executive.com"
                ),
                NewsArticle(
                    id: "2",
                    title: "IMO 2024 Environmental Regulations Take Effect",
                    summary: "New international maritime environmental standards are now in force, affecting global shipping operations.",
                    source: "Lloyd's List",
                    publishedAt: Date().addingTimeInterval(-172800),
                    category: .environmental,
                    url: "https://lloydslist.com"
                ),
                NewsArticle(
                    id: "3",
                    title: "OSV Market Recovery Shows Strong Growth",
                    summary: "Offshore support vessel demand increases as oil and gas exploration activities expand worldwide.",
                    source: "Offshore Magazine",
                    publishedAt: Date().addingTimeInterval(-259200),
                    category: .industry,
                    url: "https://offshore-mag.com"
                )
            ]
        }
        
        isLoading = false
    }
    
    private func categorizeArticle(_ title: String) -> NewsArticle.Category {
        let lowercased = title.lowercased()
        if lowercased.contains("regulation") || lowercased.contains("compliance") || lowercased.contains("uscg") {
            return .regulation
        } else if lowercased.contains("environment") || lowercased.contains("emission") || lowercased.contains("pollution") {
            return .environmental
        } else if lowercased.contains("safety") || lowercased.contains("accident") || lowercased.contains("incident") {
            return .safety
        } else if lowercased.contains("technology") || lowercased.contains("autonomous") || lowercased.contains("digital") {
            return .technology
        } else {
            return .industry
        }
    }
}

// MARK: - Supporting Models

struct NewsResponse: Codable {
    let articles: [APIArticle]
    
    struct APIArticle: Codable {
        let id: String
        let title: String
        let summary: String?
        let source: String
        let publishedAt: String
        let url: String
        let imageUrl: String?
        let category: String?
    }
}

struct NewsArticle: Identifiable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let publishedAt: Date
    let category: Category
    let url: String
    
    enum Category: String, CaseIterable {
        case regulation = "regulation"
        case environmental = "environmental"
        case industry = "industry"
        case safety = "safety"
        case technology = "technology"
        
        var displayName: String {
            switch self {
            case .regulation: return "Regulation"
            case .environmental: return "Environmental"
            case .industry: return "Industry"
            case .safety: return "Safety"
            case .technology: return "Technology"
            }
        }
        
        var color: Color {
            switch self {
            case .regulation: return .blue
            case .environmental: return .green
            case .industry: return .orange
            case .safety: return .red
            case .technology: return .purple
            }
        }
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: publishedAt, relativeTo: Date())
    }
}

// MARK: - Supporting Views

struct ArticleCard: View {
    let article: NewsArticle
    @State private var isBookmarked = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category and time
            HStack {
                Text(article.category.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(article.category.color.opacity(0.2))
                    .foregroundColor(article.category.color)
                    .cornerRadius(6)
                
                Spacer()
                
                Text(article.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Title
            Text(article.title)
                .font(.headline)
                .lineLimit(2)
            
            // Summary
            Text(article.summary)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            // Source and actions
            HStack {
                Text(article.source)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Bookmark button
                Button(action: {
                    isBookmarked.toggle()
                    if isBookmarked {
                        saveArticleToLibrary(article)
                    }
                }) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundColor(isBookmarked ? .blue : .secondary)
                }
                
                // Open link button
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
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .onAppear {
            checkIfBookmarked()
        }
    }
    
    private func saveArticleToLibrary(_ article: NewsArticle) {
        let bookmark = BookmarkedArticle(article: article)
        // Save to UserDefaults temporarily until BookmarkService is properly added to target
        var existingBookmarks = UserDefaults.standard.array(forKey: "BookmarkedArticles") as? [Data] ?? []
        if let data = try? JSONEncoder().encode(bookmark) {
            existingBookmarks.append(data)
            UserDefaults.standard.set(existingBookmarks, forKey: "BookmarkedArticles")
        }
        NotificationCenter.default.post(name: NSNotification.Name("ArticleBookmarked"), object: article)
    }

    private func checkIfBookmarked() {
        // Load from UserDefaults temporarily until BookmarkService is properly added to target
        guard let dataArray = UserDefaults.standard.array(forKey: "BookmarkedArticles") as? [Data] else {
            isBookmarked = false
            return
        }
        let bookmarks = dataArray.compactMap { try? JSONDecoder().decode(BookmarkedArticle.self, from: $0) }
        isBookmarked = bookmarks.contains { $0.id == article.id }
    }
}

struct ArticleCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 80, height: 20)
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 60, height: 12)
            }
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemBackground))
                .frame(height: 40)
            
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemBackground))
                .frame(height: 60)
            
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 100, height: 12)
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 20, height: 12)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    DiscoverView()
}