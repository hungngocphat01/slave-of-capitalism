import Foundation
import Observation

@Observable
final class AppSettings {

    private enum Keys {
        static let currency = "currency"
        static let decimals = "decimals"
        static let language = "language"
        static let databasePath = "databasePath"
    }

    private let defaults: UserDefaults

    var currency: String {
        didSet { defaults.set(currency, forKey: Keys.currency) }
    }

    var decimals: Int {
        didSet { defaults.set(decimals, forKey: Keys.decimals) }
    }

    var language: String {
        didSet { defaults.set(language, forKey: Keys.language) }
    }

    var databasePath: String {
        didSet { defaults.set(databasePath, forKey: Keys.databasePath) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currency = defaults.string(forKey: Keys.currency) ?? "¥"
        self.decimals = defaults.object(forKey: Keys.decimals) as? Int ?? 0
        self.language = defaults.string(forKey: Keys.language) ?? "en"
        self.databasePath = defaults.string(forKey: Keys.databasePath) ?? ""
    }
}
