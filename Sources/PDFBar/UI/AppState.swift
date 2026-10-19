import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

extension ParamKind {
    var defaultValue: Any {
        switch self {
        case .text(let d, _):      return d
        case .pages(let d):        return d
        case .int(let d, _, _):    return d
        case .double(let d, _, _): return d
        case .toggle(let d):       return d
        case .choice(_, let d):    return d
        case .file:                return ""
        }
    }
}

final class AppState: ObservableObject {

    @Published var selectedToolID: String = "merge"
    @Published var inputs: [URL] = []
    @Published var auxFile: URL?
    @Published var params: [String: Any] = [:]
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var status: String = ""
    @Published var results: [URL] = []
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var outputDir: URL = AppState.defaultOutputDir
    @Published var serverURL: String = "http://localhost:8080"

    static var defaultOutputDir: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = downloads.appendingPathComponent("PDFBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var tool: Tool? { ToolRegistry.tool(selectedToolID) }

    init() {
        resetParams(for: ToolRegistry.tool(selectedToolID))
    }

    // MARK: Selection

    func select(toolID: String) {
        guard toolID != selectedToolID else { return }
        selectedToolID = toolID
        resetParams(for: ToolRegistry.tool(toolID))
        auxFile = nil
        results = []
        errorMessage = nil
        status = ""
    }

    private func resetParams(for tool: Tool?) {
        var fresh: [String: Any] = [:]
        for param in tool?.params ?? [] {
            fresh[param.key] = param.kind.defaultValue
        }
        params = fresh
    }

    // MARK: Inputs

    func addInput(_ url: URL) {
        guard let tool else { return }
        if !tool.multiInput {
            inputs = [url]
        } else if !inputs.contains(url) {
            inputs.append(url)
        }
        results = []
        errorMessage = nil
    }

    func removeInput(_ url: URL) {
        inputs.removeAll { $0 == url }
    }

    func clearInputs() { inputs = [] }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = tool?.multiInput ?? false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image]
        panel.message = tool?.multiInput == true ? "Choose files" : "Choose a file"
        if panel.runModal() == .OK {
            for url in panel.urls { addInput(url) }
        }
    }

    func chooseAuxFile(_ param: ToolParam) {
        guard case .file(let extensions, let prompt) = param.kind else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = prompt
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            auxFile = panel.url
            params[param.key] = panel.url?.lastPathComponent ?? ""
        }
    }

    func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Where should results go?"
        if panel.runModal() == .OK, let url = panel.url { outputDir = url }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self?.addInput(url) }
            }
        }
        return accepted
    }

    // MARK: Run

    var canRun: Bool {
        guard let tool else { return false }
        if tool.remoteOnly { return true }
        if tool.id == "url2pdf" { return !(params["url"] as? String ?? "").isEmpty }
        return !inputs.isEmpty
    }

    func run() {
        guard let tool, !isRunning else { return }
        errorMessage = nil
        results = []

        if tool.remoteOnly {
            runOnServer(tool)
            return
        }

        isRunning = true
        progress = 0
        status = "Working…"

        let context = RunContext(
            inputs: inputs,
            auxFile: auxFile,
            params: params,
            outputDir: outputDir,
            progress: { [weak self] value, message in
                DispatchQueue.main.async {
                    self?.progress = value
                    self?.status = message
                }
            }
        )

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let urls = try PDFEngine.run(tool.id, context)
                DispatchQueue.main.async {
                    self.results = urls
                    self.isRunning = false
                    self.progress = 1
                    self.status = urls.count == 1
                        ? "Done — \(urls[0].lastPathComponent)"
                        : "Done — \(urls.count) files"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.errorMessage = error.localizedDescription
                    self.status = "Failed"
                }
            }
        }
    }

    private func runOnServer(_ tool: Tool) {
        guard let url = URL(string: serverURL) else {
            errorMessage = "That server address is not a valid URL."
            return
        }
        if tool.id == "stirling:open" {
            NSWorkspace.shared.open(url)
            status = "Opened \(url.absoluteString)"
            return
        }
        // The other server tools open the matching page in the Stirling UI.
        let paths: [String: String] = [
            "stirling:editor":     "/edit",
            "stirling:office2pdf": "/convert/office",
            "stirling:pdf2word":   "/convert/pdf-to-word",
            "stirling:pdf2ppt":    "/convert/pdf-to-presentation",
            "stirling:pdf2pdfa":   "/convert/pdf-to-pdfa",
            "stirling:extractimg": "/convert/extract-images"
        ]
        let target = url.appendingPathComponent(paths[tool.id] ?? "/")
        NSWorkspace.shared.open(target)
        status = "Opened \(tool.name) on the Stirling server"
    }

    func revealResults() {
        guard let first = results.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first])
    }

    // MARK: Bindings

    func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { self.params[key] as? String ?? "" },
            set: { self.params[key] = $0 }
        )
    }

    func intBinding(_ key: String) -> Binding<Int> {
        Binding(
            get: { self.params[key] as? Int ?? 0 },
            set: { self.params[key] = $0 }
        )
    }

    func doubleBinding(_ key: String) -> Binding<Double> {
        Binding(
            get: { self.params[key] as? Double ?? 0 },
            set: { self.params[key] = $0 }
        )
    }

    func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { self.params[key] as? Bool ?? false },
            set: { self.params[key] = $0 }
        )
    }

    func isVisible(_ param: ToolParam) -> Bool {
        guard let rule = param.visibleWhen else { return true }
        return rule(RunContext(inputs: inputs, auxFile: auxFile, params: params, outputDir: outputDir))
    }
}
