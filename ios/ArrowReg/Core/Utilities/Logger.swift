import Foundation
import os.log

struct Logger {
    private let logger: os.Logger
    
    init(category: String, subsystem: String = "com.yourcompany.arrowreg") {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }
    
    func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message)")
        #endif
    }
    
    func info(_ message: String) {
        logger.info("\(message)")
    }
    
    func warning(_ message: String) {
        logger.warning("\(message)")
    }
    
    func error(_ message: String) {
        logger.error("\(message)")
    }
    
    func fault(_ message: String) {
        logger.fault("\(message)")
    }
}

// Convenience loggers
extension Logger {
    static let search = Logger(category: "Search")
    static let network = Logger(category: "Network")
    static let ui = Logger(category: "UI")
    static let app = Logger(category: "App")
}