import Foundation

extension ProcessInfo {
    /// Whether `key` is set, used to gate debug behaviour.
    func flag(forKey key: String) -> Bool {
        environment[key] != nil
    }

    /// The value of `key` parsed as a `Double`, or `nil` when it is unset or unparseable.
    func double(forKey key: String) -> Double? {
        guard let raw = environment[key], let value = Double(raw) else { return nil }
        return value
    }

    /// The value of a millisecond-valued `key`, in seconds.
    func seconds(forKey key: String) -> Double? {
        guard let milliseconds = double(forKey: key) else { return nil }
        return milliseconds / 1000
    }
}
