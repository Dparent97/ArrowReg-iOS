import XCTest
@testable import ArrowReg

final class BookmarkServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var service: BookmarkService!

    override func setUp() {
        defaults = UserDefaults(suiteName: "BookmarkServiceTests")
        defaults.removePersistentDomain(forName: "BookmarkServiceTests")
        service = BookmarkService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "BookmarkServiceTests")
        defaults = nil
        service = nil
    }

    func testSearchBookmarkRetrieval() {
        let result = SearchResult(id: "1", query: "test", answer: "answer", citations: [], confidence: 90, isComplete: true, isOffline: false)
        service.save(result, forKey: "BookmarkedSearches")

        let loaded: [SearchResult] = service.load(forKey: "BookmarkedSearches")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "1")
    }

    func testArticleBookmarkRetrieval() {
        let article = BookmarkedArticle(id: "a1", title: "t", summary: "s", source: "src", url: "http://example.com", date: Date())
        service.save(article, forKey: "BookmarkedArticles")

        let loaded: [BookmarkedArticle] = service.load(forKey: "BookmarkedArticles")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "a1")
    }
}
