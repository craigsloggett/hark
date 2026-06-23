import Foundation

extension ProcessInfo {
    /// Whether `key` is set, used to gate debug behaviour.
    func flag(forKey key: String) -> Bool {
        environment[key] != nil
    }
}
