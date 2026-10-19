import Foundation

// MARK: - Categories

enum ToolCategory: String, CaseIterable, Identifiable {
    case organize, convert, edit, security, advanced, server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .organize: return "Organize"
        case .convert:  return "Convert"
        case .edit:     return "Edit"
        case .security: return "Security"
        case .advanced: return "Advanced"
        case .server:   return "Stirling Server"
        }
    }

    var symbol: String {
        switch self {
        case .organize: return "square.grid.2x2"
        case .convert:  return "arrow.triangle.2.circlepath"
        case .edit:     return "pencil.and.outline"
        case .security: return "lock.shield"
        case .advanced: return "wand.and.stars"
        case .server:   return "server.rack"
        }
    }
}

// MARK: - Parameters

enum ParamKind {
    case text(default: String, placeholder: String)
    case pages(default: String)
    case int(default: Int, min: Int, max: Int)
    case double(default: Double, min: Double, max: Double)
    case toggle(default: Bool)
    case choice([String], default: Int)
    /// Auxiliary file input (e.g. a signature or stamp image).
    case file(extensions: [String], prompt: String)
}

struct ToolParam: Identifiable {
    let key: String
    let label: String
    let kind: ParamKind
    var help: String? = nil
    var visibleWhen: ((RunContext) -> Bool)? = nil

    var id: String { key }
}

// MARK: - Tool

struct Tool: Identifiable {
    let id: String
    let name: String
    let category: ToolCategory
    let symbol: String
    let summary: String
    /// Accepts more than one input file (e.g. merge, images -> pdf).
    var multiInput: Bool = false
    /// Auxiliary file types accepted as secondary inputs.
    var params: [ToolParam] = []
    /// Requires the Stirling-PDF server rather than the native engine.
    var remoteOnly: Bool = false
    /// One-line note shown under the tool title.
    var note: String? = nil

    var acceptsMultiple: Bool { multiInput }
}

// MARK: - Run context

struct RunContext {
    let inputs: [URL]
    let auxFile: URL?
    let params: [String: Any]
    let outputDir: URL
    var progress: ((Double, String) -> Void)? = nil

    func string(_ key: String, _ fallback: String = "") -> String {
        (params[key] as? String) ?? fallback
    }
    func int(_ key: String, _ fallback: Int = 0) -> Int {
        if let v = params[key] as? Int { return v }
        if let v = params[key] as? Double { return Int(v) }
        if let s = params[key] as? String, let v = Int(s) { return v }
        return fallback
    }
    func double(_ key: String, _ fallback: Double = 0) -> Double {
        if let v = params[key] as? Double { return v }
        if let v = params[key] as? Int { return Double(v) }
        if let s = params[key] as? String, let v = Double(s) { return v }
        return fallback
    }
    func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        (params[key] as? Bool) ?? fallback
    }

    /// Value of a choice param, resolved to the option string.
    func choice(_ key: String, options: [String], fallback: Int = 0) -> String {
        let idx = int(key, fallback)
        guard idx >= 0 && idx < options.count else { return options[fallback] }
        return options[idx]
    }
}

// MARK: - Errors

enum EngineError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

func fail(_ message: String) -> EngineError { .message(message) }
