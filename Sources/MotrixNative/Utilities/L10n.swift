import Foundation

enum L10n {
  enum Language: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var title: String {
      switch self {
      case .system: return L10n.tr("preferences.language.system")
      case .simplifiedChinese: return L10n.tr("preferences.language.simplified_chinese")
      case .english: return L10n.tr("preferences.language.english")
      }
    }
  }

  private static let languageLock = NSLock()
  nonisolated(unsafe) private static var selectedLanguage = Language.system.rawValue

  static func configure(language: String) {
    let normalized = Language(rawValue: language)?.rawValue ?? Language.system.rawValue
    languageLock.lock()
    selectedLanguage = normalized
    languageLock.unlock()
  }

  static func tr(_ key: String) -> String {
    localizedBundle.localizedString(forKey: key, value: key, table: nil)
  }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: Locale.current, arguments: arguments)
  }

  private static var localizedBundle: Bundle {
    languageLock.lock()
    let language = selectedLanguage
    languageLock.unlock()
    guard
      language != Language.system.rawValue,
      let path = Bundle.main.path(forResource: language, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else {
      return .main
    }
    return bundle
  }
}
