import Foundation
import os.log

/// High-performance logging system that minimizes impact on app performance
/// Only logs in DEBUG builds, uses os_log for better performance
@MainActor
class PerformanceLogger {
    static let shared = PerformanceLogger()
    
    // Use os_log for better performance than print()
    private let logger = Logger(subsystem: "com.chenchungwan.LotusPlannerV3", category: "Performance")
    
    // Only enable logging in DEBUG builds
    #if DEBUG
    private let isLoggingEnabled = true
    #else
    private let isLoggingEnabled = false
    #endif
    
    private init() {}
    
    /// High-performance logging that only executes in DEBUG builds
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard isLoggingEnabled else { return }
        
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function): \(message)"
        
        switch level {
        case .debug:
            logger.debug("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .warning:
            logger.warning("\(logMessage)")
        case .error:
            logger.error("\(logMessage)")
        }
    }
    
    /// Conditional logging for expensive operations
    func logIf(_ condition: Bool, _ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard condition && isLoggingEnabled else { return }
        log(message, level: level, file: file, function: function, line: line)
    }
    
    /// Performance-critical logging that can be disabled
    func logPerformance(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        // Only log performance-critical items in DEBUG builds
        log(message, level: .info, file: file, function: function, line: line)
        #endif
    }
}

enum LogLevel {
    case debug
    case info
    case warning
    case error
}

// MARK: - Convenience Extensions
extension PerformanceLogger {
    /// Quick debug logging
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    /// Quick info logging
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    /// Quick warning logging
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    /// Quick error logging
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}

// MARK: - Global Convenience Functions
/// High-performance logging that only works in DEBUG builds
@MainActor
func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    PerformanceLogger.shared.debug(message, file: file, function: function, line: line)
}

@MainActor
func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    PerformanceLogger.shared.info(message, file: file, function: function, line: line)
}

@MainActor
func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    PerformanceLogger.shared.warning(message, file: file, function: function, line: line)
}

@MainActor
func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    PerformanceLogger.shared.error(message, file: file, function: function, line: line)
}

/// Performance-critical logging
@MainActor
func logPerformance(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    PerformanceLogger.shared.logPerformance(message, file: file, function: function, line: line)
}
