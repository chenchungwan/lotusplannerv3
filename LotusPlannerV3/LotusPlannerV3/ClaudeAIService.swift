import Foundation

struct AITaskSuggestion: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var notes: String?
    var dueDate: Date?
    var durationMinutes: Int?
}

enum AITaskAgentActionType: String, Codable, CaseIterable {
    case createTask
    case updateTaskDate
    case moveTaskToList
}

struct AITaskAgentAction: Identifiable, Equatable {
    var id = UUID()
    var type: AITaskAgentActionType
    var title: String?
    var notes: String?
    var dueDate: Date?
    var durationMinutes: Int?
    var taskQuery: String?
    var targetListName: String?
    var targetAccountKind: GoogleAuthManager.AccountKind?
}

enum ClaudeAIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(Int, String)
    case responseTooLong
    case noSuggestions

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key in Settings before using AI task entry."
        case .invalidResponse:
            return "Claude returned a response the app could not read."
        case .requestFailed(let statusCode, let message):
            return "Claude request failed (\(statusCode)): \(message)"
        case .responseTooLong:
            return "Claude's response was too long and was cut off. Try a smaller request."
        case .noSuggestions:
            return "Claude did not return any task suggestions."
        }
    }
}

final class ClaudeAIService {
    static let shared = ClaudeAIService()

    static let apiKeyAccount = "anthropic_api_key"

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"
    private let version = "2023-06-01"

    private init() {}

    var hasAPIKey: Bool {
        (try? apiKey()) != nil
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try KeychainManager.shared.delete(for: Self.apiKeyAccount)
        } else {
            try KeychainManager.shared.saveString(trimmed, for: Self.apiKeyAccount)
        }
    }

    func apiKeyPreview() -> String? {
        guard let key = try? apiKey(), key.count >= 8 else { return nil }
        return "\(key.prefix(7))...\(key.suffix(4))"
    }

    func suggestTasks(from input: String, referenceDate: Date = Date()) async throws -> [AITaskSuggestion] {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return [] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(
            ClaudeMessageRequest(
                model: model,
                maxTokens: 2500,
                system: systemPrompt(referenceDate: referenceDate),
                messages: [
                    ClaudeInputMessage(role: "user", content: trimmedInput)
                ]
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                devLog("Claude request failed: invalid HTTP response", level: .error, category: .tasks)
                throw ClaudeAIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                let decodedError = decodeErrorMessage(from: data)
                let message = decodedError?.message ?? "Unknown error"
                let requestId = decodedError?.requestId ?? "n/a"
                devLog(
                    "Claude request failed status=\(httpResponse.statusCode) requestId=\(requestId) message=\(message)",
                    level: .error,
                    category: .tasks
                )
                throw ClaudeAIError.requestFailed(httpResponse.statusCode, message)
            }

            let message = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
            if message.stopReason == "max_tokens" {
                devLog("Claude response parsing failed: response hit max_tokens before valid JSON was complete", level: .error, category: .tasks)
                throw ClaudeAIError.responseTooLong
            }
            guard let text = message.content.first(where: { $0.type == "text" })?.text else {
                devLog("Claude request failed: response did not include text content", level: .error, category: .tasks)
                throw ClaudeAIError.invalidResponse
            }

            let suggestions: [AITaskSuggestion]
            do {
                suggestions = try decodeSuggestions(from: text)
            } catch {
                devLog(
                    "Claude response parsing failed: \(error.localizedDescription) raw=\(text.prefix(1000))",
                    level: .error,
                    category: .tasks
                )
                throw ClaudeAIError.invalidResponse
            }
            guard !suggestions.isEmpty else {
                devLog("Claude request failed: no task suggestions returned", level: .error, category: .tasks)
                throw ClaudeAIError.noSuggestions
            }
            return suggestions
        } catch let error as ClaudeAIError {
            throw error
        } catch {
            devLog("Claude request failed: \(error.localizedDescription)", level: .error, category: .tasks)
            throw error
        }
    }

    func planTaskActions(
        from input: String,
        taskContext: String,
        referenceDate: Date = Date()
    ) async throws -> [AITaskAgentAction] {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return [] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONEncoder().encode(
            ClaudeMessageRequest(
                model: model,
                maxTokens: 2500,
                system: agentSystemPrompt(referenceDate: referenceDate, taskContext: taskContext),
                messages: [
                    ClaudeInputMessage(role: "user", content: trimmedInput)
                ]
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                devLog("Claude task agent failed: invalid HTTP response", level: .error, category: .tasks)
                throw ClaudeAIError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                let decodedError = decodeErrorMessage(from: data)
                let message = decodedError?.message ?? "Unknown error"
                let requestId = decodedError?.requestId ?? "n/a"
                devLog(
                    "Claude task agent failed status=\(httpResponse.statusCode) requestId=\(requestId) message=\(message)",
                    level: .error,
                    category: .tasks
                )
                throw ClaudeAIError.requestFailed(httpResponse.statusCode, message)
            }

            let message = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
            if message.stopReason == "max_tokens" {
                devLog("Claude task agent failed: response hit max_tokens before valid JSON was complete", level: .error, category: .tasks)
                throw ClaudeAIError.responseTooLong
            }
            guard let text = message.content.first(where: { $0.type == "text" })?.text else {
                devLog("Claude task agent failed: response did not include text content", level: .error, category: .tasks)
                throw ClaudeAIError.invalidResponse
            }

            let actions: [AITaskAgentAction]
            do {
                actions = try decodeAgentActions(from: text)
            } catch {
                devLog(
                    "Claude task agent parsing failed: \(error.localizedDescription) raw=\(text.prefix(1000))",
                    level: .error,
                    category: .tasks
                )
                throw ClaudeAIError.invalidResponse
            }
            guard !actions.isEmpty else {
                devLog("Claude task agent failed: no actions returned", level: .error, category: .tasks)
                throw ClaudeAIError.noSuggestions
            }
            return actions
        } catch let error as ClaudeAIError {
            throw error
        } catch {
            devLog("Claude task agent failed: \(error.localizedDescription)", level: .error, category: .tasks)
            throw error
        }
    }

    private func apiKey() throws -> String {
        do {
            let key = try KeychainManager.shared.loadString(for: Self.apiKeyAccount)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ClaudeAIError.missingAPIKey }
            return key
        } catch KeychainManager.KeychainError.itemNotFound {
            throw ClaudeAIError.missingAPIKey
        }
    }

    private func systemPrompt(referenceDate: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        let today = dateFormatter.string(from: referenceDate)

        return """
        You convert natural language planner input into concise task suggestions.
        Today is \(today) in the user's local timezone.
        Return only valid JSON with this exact shape:
        {"tasks":[{"title":"string","notes":"string or null","dueDate":"yyyy-MM-dd or null","durationMinutes":number or null}]}
        Rules:
        - If the input is a large goal or project, break it into 3 to 7 concrete next-action tasks.
        - If the input is a single task, return one task.
        - Keep titles short and actionable.
        - Use dueDate only when the user states or clearly implies a date.
        - Use durationMinutes only when the user states or clearly implies a duration.
        - Do not invent private details, contacts, or unnecessary notes.
        """
    }

    private func agentSystemPrompt(referenceDate: Date, taskContext: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        let today = dateFormatter.string(from: referenceDate)

        return """
        You are a planner task agent. Convert the user's request into task actions.
        Today is \(today) in the user's local timezone.
        Return only valid JSON with this exact shape:
        {"actions":[{"type":"createTask|updateTaskDate|moveTaskToList","title":"string or null","notes":"string or null","dueDate":"yyyy-MM-dd or null","durationMinutes":number or null","taskQuery":"string or null","targetListName":"string or null","targetAccount":"personal or professional or null"}]}

        Rules:
        - Use createTask for new tasks and project breakdowns.
        - Use updateTaskDate for requests like move/reschedule/push "xyz" to tomorrow, Friday, next week, or a specific date.
        - Use moveTaskToList for requests like move "xyz" to Work, Inbox, Errands, or another list.
        - For updateTaskDate and moveTaskToList, set taskQuery to the user's words identifying the existing task.
        - Use targetListName only for list moves.
        - Use targetAccount only if the user clearly mentions personal or professional/work.
        - Do not invent tasks for management requests. If the user asks to move an existing task, return a management action.
        - Keep createTask titles short and actionable.
        - Use dueDate only when the user states or clearly implies a date.
        - Use durationMinutes only when the user states or clearly implies a duration.

        Available planner context:
        \(taskContext)
        """
    }

    private func decodeAgentActions(from text: String) throws -> [AITaskAgentAction] {
        let jsonText = extractJSONObject(from: text)
        guard let data = jsonText.data(using: .utf8) else {
            throw ClaudeAIError.invalidResponse
        }
        let items: [ClaudeTaskAgentItem]
        if let decoded = try? JSONDecoder().decode(ClaudeTaskAgentResponse.self, from: data) {
            items = decoded.actions
        } else {
            items = try JSONDecoder().decode([ClaudeTaskAgentItem].self, from: data)
        }

        return items.compactMap { item in
            guard let type = item.type else { return nil }
            return AITaskAgentAction(
                type: type,
                title: item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                notes: item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                dueDate: item.dueDate.flatMap(Self.taskDateFormatter.date(from:)),
                durationMinutes: item.durationMinutes,
                taskQuery: item.taskQuery?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                targetListName: item.targetListName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                targetAccountKind: item.targetAccountKind
            )
        }
    }

    private func decodeSuggestions(from text: String) throws -> [AITaskSuggestion] {
        let jsonText = extractJSONObject(from: text)
        guard let data = jsonText.data(using: .utf8) else {
            throw ClaudeAIError.invalidResponse
        }
        let items: [ClaudeTaskSuggestionItem]
        if let decoded = try? JSONDecoder().decode(ClaudeTaskSuggestionResponse.self, from: data) {
            items = decoded.tasks
        } else {
            items = try JSONDecoder().decode([ClaudeTaskSuggestionItem].self, from: data)
        }

        return items.compactMap { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return AITaskSuggestion(
                title: title,
                notes: item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                dueDate: item.dueDate.flatMap(Self.taskDateFormatter.date(from:)),
                durationMinutes: item.durationMinutes
            )
        }
    }

    private func extractJSONObject(from text: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let objectStart = trimmed.firstIndex(of: "{")
        let arrayStart = trimmed.firstIndex(of: "[")
        let start: String.Index?
        let end: String.Index?

        if let objectStart, let arrayStart {
            if objectStart < arrayStart {
                start = objectStart
                end = trimmed.lastIndex(of: "}")
            } else {
                start = arrayStart
                end = trimmed.lastIndex(of: "]")
            }
        } else if let objectStart {
            start = objectStart
            end = trimmed.lastIndex(of: "}")
        } else if let arrayStart {
            start = arrayStart
            end = trimmed.lastIndex(of: "]")
        } else {
            start = nil
            end = nil
        }

        guard let start, let end else {
            return text
        }
        return String(trimmed[start...end])
    }

    private func decodeErrorMessage(from data: Data) -> DecodedClaudeError? {
        if let decoded = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
            return DecodedClaudeError(message: decoded.error.message, requestId: decoded.requestId)
        }
        if let message = String(data: data, encoding: .utf8) {
            return DecodedClaudeError(message: message, requestId: nil)
        }
        return nil
    }

    private static let taskDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

private struct ClaudeMessageRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeInputMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

private struct ClaudeInputMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeMessageResponse: Decodable {
    let content: [ClaudeContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

private struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
}

private struct ClaudeTaskSuggestionResponse: Decodable {
    let tasks: [ClaudeTaskSuggestionItem]
}

private struct ClaudeTaskAgentResponse: Decodable {
    let actions: [ClaudeTaskAgentItem]
}

private struct ClaudeTaskAgentItem: Decodable {
    let type: AITaskAgentActionType?
    let title: String?
    let notes: String?
    let dueDate: String?
    let durationMinutes: Int?
    let taskQuery: String?
    let targetListName: String?
    let targetAccountKind: GoogleAuthManager.AccountKind?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.type = Self.decodeActionType(from: container)
        self.title = Self.decodeString(for: ["title", "task", "name"], from: container)
        self.notes = Self.decodeString(for: ["notes", "note", "description"], from: container)
        self.dueDate = Self.decodeString(for: ["dueDate", "due_date", "date"], from: container)
        self.durationMinutes = Self.decodeInt(
            for: ["durationMinutes", "duration_minutes", "estimatedMinutes", "estimated_minutes", "minutes"],
            from: container
        )
        self.taskQuery = Self.decodeString(for: ["taskQuery", "task_query", "query", "existingTask"], from: container)
        self.targetListName = Self.decodeString(for: ["targetListName", "target_list_name", "list", "listName"], from: container)
        self.targetAccountKind = Self.decodeAccountKind(from: container)
    }

    private static func decodeActionType(
        from container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> AITaskAgentActionType? {
        guard let raw = decodeString(for: ["type", "action", "operation"], from: container)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return nil }

        switch raw {
        case "createtask", "create_task", "create", "addtask", "add_task", "add":
            return .createTask
        case "updatetaskdate", "update_task_date", "movedate", "move_date", "reschedule", "schedule":
            return .updateTaskDate
        case "movetasktolist", "move_task_to_list", "movelist", "move_list", "move":
            return .moveTaskToList
        default:
            return AITaskAgentActionType(rawValue: raw)
        }
    }

    private static func decodeAccountKind(
        from container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> GoogleAuthManager.AccountKind? {
        guard let raw = decodeString(for: ["targetAccount", "target_account", "account"], from: container)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return nil }

        switch raw {
        case "personal":
            return .account1
        case "professional", "work", "business":
            return .account2
        default:
            return nil
        }
    }

    private static func decodeString(
        for keys: [String],
        from container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> String? {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value = try? container.decodeIfPresent(String.self, forKey: codingKey),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func decodeInt(
        for keys: [String],
        from container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> Int? {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                return value
            }
            if let stringValue = try? container.decodeIfPresent(String.self, forKey: codingKey),
               let value = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }
}

private struct ClaudeTaskSuggestionItem: Decodable {
    let title: String
    let notes: String?
    let dueDate: String?
    let durationMinutes: Int?

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let title = try? singleValue.decode(String.self) {
            self.title = title
            self.notes = nil
            self.dueDate = nil
            self.durationMinutes = nil
            return
        }

        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.title = Self.decodeString(
            for: ["title", "task", "name"],
            from: container
        ) ?? ""
        self.notes = Self.decodeString(
            for: ["notes", "note", "description"],
            from: container
        )
        self.dueDate = Self.decodeString(
            for: ["dueDate", "due_date", "date"],
            from: container
        )
        self.durationMinutes = Self.decodeInt(
            for: ["durationMinutes", "duration_minutes", "estimatedMinutes", "estimated_minutes", "minutes"],
            from: container
        )
    }

    private static func decodeString(
        for keys: [String],
        from container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> String? {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value = try? container.decodeIfPresent(String.self, forKey: codingKey),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func decodeInt(
        for keys: [String],
        from container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> Int? {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                return value
            }
            if let stringValue = try? container.decodeIfPresent(String.self, forKey: codingKey),
               let value = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private struct ClaudeErrorResponse: Decodable {
    let error: ClaudeErrorDetail
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case error
        case requestId = "request_id"
    }
}

private struct ClaudeErrorDetail: Decodable {
    let message: String
}

private struct DecodedClaudeError {
    let message: String
    let requestId: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
