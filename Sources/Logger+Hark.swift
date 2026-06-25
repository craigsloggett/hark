import OSLog

extension Logger {
    /// A logger in Hark's subsystem for the given category.
    init(category: String) {
        self.init(subsystem: "com.craigsloggett.hark", category: category)
    }
}
