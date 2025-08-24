import SwiftUI

struct ClearOnSwipeGesture: ViewModifier {
    let action: () -> Void
    @State private var hasTriggeredHaptic = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width < -50 && !hasTriggeredHaptic {
                        hasTriggeredHaptic = true
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }
                .onEnded { value in
                    hasTriggeredHaptic = false
                    if value.translation.width < -100 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            action()
                        }
                    }
                }
        )
    }
}

extension View {
    func clearOnSwipeGesture(action: @escaping () -> Void) -> some View {
        modifier(ClearOnSwipeGesture(action: action))
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @StateObject private var searchService = SearchService.shared
    @FocusState private var isSearchFieldFocused: Bool

    // UI State
    @State private var showingOptions = false
    @State private var showingHistory = false
    @State private var followUpQuery = ""
    @State private var showingFollowUpInput = false
    @State private var showScrollToTop = false
    
    // Settings
    @AppStorage("search.history.enabled") private var historyEnabled = true
    
    var isPristine: Bool {
        viewModel.searchQuery.isEmpty && viewModel.results.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background Layer
                backgroundLayer
                
                // Main Content
                VStack {
                    if isPristine {
                        minimalEntryState
                    } else {
                        searchResultsState
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingOptions) {
                OptionsSheet(
                    historyEnabled: $historyEnabled,
                    onClearPage: clearPage,
                    onClearHistory: clearHistory
                )
            }
            .sheet(isPresented: $showingHistory) {
                HistoryTray(
                    enabled: historyEnabled,
                    onQuerySelected: { query in
                        viewModel.searchQuery = query
                        showingHistory = false
                        performSearch()
                    }
                )
            }
            .onAppear {
                // Background images disabled
            }
            .alert("Search Error", isPresented: $viewModel.showingError) {
                Button("OK") { }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "Unknown error occurred")
            }
        }
    }
    
    // MARK: - Minimal Entry State
    
    private var minimalEntryState: some View {
        VStack(spacing: 0) {
            // Top spacer to center content
            Spacer()
            
            // Options icon (top right)
            HStack {
                Spacer()
                Button(action: { showingOptions = true }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                        .padding()
                }
            }
            .padding(.top, 60) // Account for safe area
            
            Spacer()
            
            // Centered search input
            MinimalSearchBar(
                query: $viewModel.searchQuery,
                isLoading: viewModel.isSearching,
                onSubmit: performSearch,
                onClear: clearSearchQuery
            )
            .focused($isSearchFieldFocused)
            .padding(.horizontal, 32)
            
            // Bottom spacer (larger to account for tab bar)
            Spacer()
            
            Spacer()
        }
    }
    
    // MARK: - Search Results State
    
    private var searchResultsState: some View {
        VStack(spacing: 0) {
            // Compact header with search bar and options
            compactHeader
                .padding()
                .background(.ultraThinMaterial)
            
            // Results content
            ScrollView(.vertical, showsIndicators: true) {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 16) {
                        // Top anchor point for scroll-to-top
                        Color.clear
                            .frame(height: 1)
                            .id("top")
                        
                        if viewModel.isSearching {
                            searchingView
                                .id("searching")
                        } else {
                            ForEach(viewModel.results, id: \.id) { result in
                                SearchResultCard(result: result) {
                                    viewModel.bookmarkResult(result)
                                }
                                .id(result.id)
                                .clearOnSwipeGesture {
                                    clearPage()
                                }
                                .onAppear {
                                    // Show scroll to top button when there are multiple results
                                    showScrollToTop = viewModel.results.count > 1
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 20) // Extra bottom padding for better scrolling
                    
                    // Follow-up question section
                    if !viewModel.results.isEmpty && searchService.isOnlineMode && searchService.currentThreadId != nil {
                        VStack(spacing: 12) {
                            // Section header
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .foregroundColor(.blue)
                                Text("Ask a follow-up question")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            // Follow-up input
                            HStack {
                                TextField("Continue the conversation...", text: $followUpQuery)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onSubmit {
                                        performFollowUp()
                                    }
                                
                                Button(action: { performFollowUp() }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(followUpQuery.isEmpty ? .gray : .blue)
                                }
                                .disabled(followUpQuery.isEmpty || viewModel.isSearching)
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .id("followup-section")
                    }
                    
                    // Add extra bottom padding to ensure scrollability
                    Color.clear
                        .frame(height: 100)
                        .id("bottom-spacer")
                }
                .overlay(
                    // Scroll to top button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            if showScrollToTop && viewModel.results.count > 1 {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.6)) {
                                        // We'll handle scroll-to-top in the button itself
                                    }
                                }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .background(Circle().fill(.blue))
                                        .shadow(radius: 4)
                                }
                                .padding(.trailing, 20)
                                .padding(.bottom, 100)
                            }
                        }
                    }
                )
            }
            .clearOnSwipeGesture {
                clearPage()
            }
        }
    }
    
    // MARK: - Components
    
    private var backgroundLayer: some View {
        // Clean dark background
        LinearGradient(
            colors: [.black, .gray.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var compactHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                // Compact search bar
                MinimalSearchBar(
                    query: $viewModel.searchQuery,
                    isLoading: viewModel.isSearching,
                    onSubmit: performSearch,
                    onClear: clearSearchQuery,
                    isCompact: true
                )
                .focused($isSearchFieldFocused)
                
                // Options button
                Button(action: { showingOptions = true }) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                
                // History button
                if historyEnabled {
                    Button(action: { showingHistory = true }) {
                        Image(systemName: "clock")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
            }
            
            // Subtle swipe hint
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption2)
                    Text("Swipe left to clear")
                        .font(.caption2)
                }
                .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }
    
    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Searching maritime regulations...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        guard !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isSearchFieldFocused = false
        viewModel.performStreamingSearch()
    }
    
    private func clearSearchQuery() {
        viewModel.searchQuery = ""
    }
    
    private func clearPage() {
        viewModel.searchQuery = ""
        viewModel.results = []
        viewModel.error = nil
        showingOptions = false
    }
    
    private func clearHistory() {
        searchService.clearHistory()
        showingOptions = false
    }
    
    private func performFollowUp() {
        guard !followUpQuery.isEmpty else { return }
        
        let query = followUpQuery
        followUpQuery = ""
        
        // Perform the search - the automatic scrolling will be handled by the view model
        viewModel.performFollowUpSearch(query)
    }
}

// MARK: - Supporting Components

struct MinimalSearchBar: View {
    @Binding var query: String
    let isLoading: Bool
    let onSubmit: () -> Void
    let onClear: () -> Void
    var isCompact: Bool = false
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Search input
            TextField("Search maritime regulations...", text: $query)
                .textFieldStyle(MinimalSearchFieldStyle(
                    isCompact: isCompact,
                    isFocused: isFocused,
                    isLoading: isLoading
                ))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .disabled(isLoading)
            
            // Clear button (inside the text field visual area)
            if !query.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .padding(.trailing, isCompact ? 8 : 12)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search maritime regulations")
        .accessibilityHint("Enter your query and press return to search")
    }
}

struct MinimalSearchFieldStyle: TextFieldStyle {
    let isCompact: Bool
    let isFocused: Bool
    let isLoading: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: isCompact ? 16 : 18))
            
            // Text field
            configuration
                .font(.system(size: isCompact ? 16 : 18, weight: .medium))
                .foregroundColor(.primary)
            
            // Loading indicator
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, isCompact ? 12 : 16)
        .padding(.vertical, isCompact ? 10 : 14)
        .background {
            RoundedRectangle(cornerRadius: isCompact ? 12 : 16)
                .fill(.ultraThinMaterial)
                .stroke(
                    isFocused ? Color.accentColor : Color.white.opacity(0.1),
                    lineWidth: isFocused ? 2 : 1
                )
        }
        .shadow(
            color: isFocused ? .accentColor.opacity(0.3) : .black.opacity(0.1),
            radius: isFocused ? 8 : 4,
            y: 2
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

struct OptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var historyEnabled: Bool
    
    let onClearPage: () -> Void
    let onClearHistory: () -> Void
    
    @State private var showingClearHistoryConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                // Search History Section
                Section("Search History") {
                    Toggle("Save search history", isOn: $historyEnabled)
                    
                    if historyEnabled {
                        Button("Clear all history", role: .destructive) {
                            showingClearHistoryConfirmation = true
                        }
                    }
                }
                
                // Actions Section
                Section("Actions") {
                    Button("Clear page") {
                        onClearPage()
                    }
                }
            }
            .navigationTitle("Search Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Clear History", isPresented: $showingClearHistoryConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    onClearHistory()
                }
            } message: {
                Text("This will permanently delete all saved search history. This action cannot be undone.")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct HistoryTray: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = SearchService.shared
    
    let enabled: Bool
    let onQuerySelected: (String) -> Void
    
    @State private var showingClearConfirmation = false
    
    var body: some View {
        NavigationStack {
            Group {
                if !enabled {
                    disabledState
                } else if searchService.searchHistory.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("Search History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                if enabled && !searchService.searchHistory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                }
            }
            .alert("Clear History", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    searchService.clearHistory()
                }
            } message: {
                Text("This will permanently delete all saved search history. This action cannot be undone.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private var disabledState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Search History Disabled")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Search history is currently disabled. Enable it in search options to start saving your queries.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Search History")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your recent searches will appear here. Start searching to build your history.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var historyList: some View {
        List {
            ForEach(Array(searchService.searchHistory.enumerated()), id: \.offset) { index, query in
                HistoryRow(
                    query: query,
                    isRecent: index < 3,
                    onSelect: {
                        onQuerySelected(query)
                    },
                    onDelete: {
                        deleteHistoryItem(at: index)
                    }
                )
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private func deleteHistoryItem(at index: Int) {
        guard index < searchService.searchHistory.count else { return }
        
        withAnimation {
            var history = searchService.searchHistory
            history.remove(at: index)
            
            UserDefaults.standard.set(history, forKey: "SearchHistory")
            searchService.searchHistory = history
        }
    }
}

struct HistoryRow: View {
    let query: String
    let isRecent: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Query icon
            Image(systemName: isRecent ? "clock.fill" : "clock")
                .font(.system(size: 16))
                .foregroundColor(isRecent ? .accentColor : .secondary)
                .frame(width: 20)
            
            // Query text
            VStack(alignment: .leading, spacing: 2) {
                Text(query)
                    .font(.system(.body, weight: isRecent ? .medium : .regular))
                    .lineLimit(2)
                
                if isRecent {
                    Text("Recent")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .padding(.vertical, 4)
    }
}

struct SearchResultCard: View {
    let result: SearchResult
    let onBookmark: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with query and bookmark
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.query)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Q&A")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Button(action: onBookmark) {
                    Image(systemName: "bookmark")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            
            // Answer content
            VStack(alignment: .leading, spacing: 8) {
                let isLongText = result.answer.split(separator: "\n").count > 8 || result.answer.count > 400
                
                if isLongText && isExpanded {
                    // Scrollable expanded text
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(result.answer)
                            .font(.body)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 500) // Larger viewing area for better readability
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                } else {
                    // Regular text (collapsed or short)
                    Text(result.answer)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(isLongText ? (isExpanded ? nil : 8) : nil)
                        .textSelection(.enabled)
                }
                
                // Show expand/collapse button for longer text
                if isLongText {
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Text(isExpanded ? "Show less" : "Show more")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            
            // Metadata footer
            HStack {
                if result.isOffline {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Label("Online", systemImage: "cloud")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Text(result.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

#Preview {
    SearchView()
        .preferredColorScheme(.dark)
}
