import Foundation
import OSLog

enum DevLogLevel {
    case debug
    case info
    case warning
    case error

    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

enum DevLogCategory: String {
    case general = "General"
    case sync = "Sync"
    case tasks = "Tasks"
    case goals = "Goals"
    case calendar = "Calendar"
    case navigation = "Navigation"
    case cloud = "Cloud"
    case auth = "Auth"
}

enum DevLogger {
    static let verboseLoggingDefaultsKey = "verboseLoggingEnabled"
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.chenchungwan.LotusPlannerV3"

    private static func shouldLog(level: DevLogLevel) -> Bool {
#if DEBUG
        switch level {
        case .error, .warning:
            return true
        case .info, .debug:
            return UserDefaults.standard.bool(forKey: verboseLoggingDefaultsKey)
        }
#else
        // In production, allow verbose logging if enabled via UserDefaults
        // This helps diagnose production CloudKit sync issues
        let verboseEnabled = UserDefaults.standard.bool(forKey: verboseLoggingDefaultsKey)
        switch level {
        case .error, .warning:
            return true  // Always log errors and warnings in production
        case .info, .debug:
            return verboseEnabled  // Only log info/debug if explicitly enabled
        }
#endif
    }

    private static func inferredLevel(from message: String, default level: DevLogLevel) -> DevLogLevel {
        let lowercased = message.lowercased()
        if message.contains("❌") || lowercased.contains("error") {
            return .error
        }
        if message.contains("⚠️") || lowercased.contains("warning") {
            return .warning
        }
        if message.contains("✅") {
            return .info
        }
        return level
    }

    private static func formatMessage(_ message: String, file: String, line: Int) -> String {
        "[\(file):\(line)] \(message)"
    }

    static func log(
        _ message: String,
        level: DevLogLevel = .debug,
        category: DevLogCategory = .general,
        file: String = #fileID,
        line: Int = #line
    ) {
        let resolvedLevel = inferredLevel(from: message, default: level)
        guard shouldLog(level: resolvedLevel) else { return }

        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        let formatted = formatMessage(message, file: file, line: line)

        switch resolvedLevel {
        case .debug:
            logger.debug("\(formatted)")
        case .info:
            logger.info("\(formatted)")
        case .warning:
            logger.log("\(formatted)")
        case .error:
            logger.error("\(formatted)")
        }
    }
}

func devLog(
    _ items: Any...,
    separator: String = " ",
    terminator: String = "\n",
    level: DevLogLevel = .debug,
    category: DevLogCategory = .general,
    file: String = #fileID,
    line: Int = #line
) {
    guard !items.isEmpty else { return }
    let message = items.map { "\($0)" }.joined(separator: separator) + terminator
    DevLogger.log(message, level: level, category: category, file: file, line: line)
}

