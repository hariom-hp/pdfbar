import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct RootView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(state: state)
                .frame(width: 250)
            Divider()
            DetailView(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var state: AppState

    private var matching: [ToolCategory: [Tool]] {
        var map: [ToolCategory: [Tool]] = [:]
        let query = state.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        for category in ToolCategory.allCases {
            let tools = ToolRegistry.tools(in: category).filter { tool in
                query.isEmpty
                    || tool.name.lowercased().contains(query)
                    || tool.summary.lowercased().contains(query)
                    || category.title.lowercased().contains(query)
            }
            if !tools.isEmpty { map[category] = tools }
        }
        return map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 15, weight: .semibold))
                Text("PDFBar")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 34)
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search tools", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(ToolCategory.allCases) { category in
                        if let tools = matching[category] {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Image(systemName: category.symbol)
                                        .font(.system(size: 9))
                                    Text(category.title.uppercased())
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .tracking(0.6)
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 3)

                                ForEach(tools) { tool in
                                    ToolRow(tool: tool, isSelected: tool.id == state.selectedToolID) {
                                        state.select(toolID: tool.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity)

            Divider()
            Button {
                state.chooseOutputDir()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(state.outputDir.lastPathComponent)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .help("Results are saved here — click to change")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.025))
    }
}

struct ToolRow: View {
    let tool: Tool
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                Text(tool.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor
                          : (hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Detail

struct DetailView: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let tool = state.tool {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(tool)
                    inputCard(tool)
                    if !tool.params.isEmpty {
                        paramsCard(tool)
                    }
                    runRow(tool)
                    if let error = state.errorMessage { errorBox(error) }
                    if !state.results.isEmpty { resultsCard() }
                }
                .padding(26)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Pick a tool")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.system(size: 20, weight: .semibold))
                    Text(tool.category.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(tool.summary)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = tool.note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inputCard(_ tool: Tool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if tool.id == "url2pdf" {
                    Label("Enter a URL below, then run.", systemImage: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if state.inputs.isEmpty {
                    DropZone(state: state, multi: tool.multiInput)
                } else {
                    ForEach(state.inputs, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(systemName: url.pathExtension.lowercased() == "pdf" ? "doc.text.fill" : "photo.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                            Text(url.lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                state.removeInput(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                    }
                    HStack(spacing: 10) {
                        Button("Choose…") { state.chooseFiles() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.accentColor)
                        Button("Clear") { state.clearInputs() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if tool.multiInput {
                            Text("Drop more to add")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func paramsCard(_ tool: Tool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(tool.params.filter { state.isVisible($0) }) { param in
                    ParamRow(state: state, param: param)
                }
            }
        }
    }

    private func runRow(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    state.run()
                } label: {
                    HStack(spacing: 6) {
                        if state.isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: tool.remoteOnly ? "safari" : "play.fill")
                                .font(.system(size: 10))
                        }
                        Text(state.isRunning ? "Working…" : (tool.remoteOnly ? "Open on server" : "Run"))
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canRun || state.isRunning)
                .keyboardShortcut(.return, modifiers: .command)

                if state.isRunning {
                    ProgressView(value: state.progress)
                        .frame(maxWidth: 180)
                }
                Text(state.status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
    }

    private func errorBox(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }

    private func resultsCard() -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Result")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Show in Finder") { state.revealResults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.accentColor)
                }
                ForEach(state.results, id: \.self) { url in
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 11))
                            Text(url.lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(byteSize(url))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func byteSize(_ url: URL) -> String {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct DropZone: View {
    @ObservedObject var state: AppState
    let multi: Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
            Text(multi ? "Drop files here" : "Drop a file here")
                .font(.system(size: 12.5, weight: .medium))
            Text("or choose from disk")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(targeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.35))
        )
        .contentShape(Rectangle())
        .onTapGesture { state.chooseFiles() }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            state.handleDrop(providers)
        }
    }
}

struct ParamRow: View {
    @ObservedObject var state: AppState
    let param: ToolParam

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(param.label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            switch param.kind {
            case .text(_, let placeholder):
                TextField(placeholder, text: state.stringBinding(param.key))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

            case .pages:
                TextField("e.g. 1-3, 5, 8-", text: state.stringBinding(param.key))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

            case .int(let def, let min, let max):
                HStack(spacing: 10) {
                    TextField("", value: state.intBinding(param.key), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 76)
                        .font(.system(size: 12))
                    Stepper("", value: state.intBinding(param.key), in: min...max)
                        .labelsHidden()
                    Text("default \(def)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }

            case .double(let def, let min, let max):
                HStack(spacing: 10) {
                    Slider(value: state.doubleBinding(param.key), in: min...max)
                        .frame(maxWidth: 220)
                    Text(String(format: "%.2f", state.doubleBinding(param.key).wrappedValue))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("default \(String(format: "%.2f", def))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }

            case .toggle:
                Toggle("", isOn: state.boolBinding(param.key))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

            case .choice(let options, _):
                // Segmented controls stop being readable past four options and
                // overflow their container, so long lists become a menu.
                if options.count > 4 {
                    Picker("", selection: state.intBinding(param.key)) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Text(option).tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 240, alignment: .leading)
                } else {
                    Picker("", selection: state.intBinding(param.key)) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Text(option).tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                }

            case .file(_, let prompt):
                HStack(spacing: 10) {
                    Button(prompt) { state.chooseAuxFile(param) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    if let aux = state.auxFile {
                        Text(aux.lastPathComponent)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let help = param.help {
                Text(help)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
