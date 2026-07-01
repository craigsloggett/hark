extension String {
    /// "1 sample" / "3 samples": a count with the noun naively pluralized by appending "s", which
    /// every counted noun in the UI satisfies.
    init(count: Int, _ noun: String) {
        self = "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
