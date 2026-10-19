import Foundation
import PDFKit
import AppKit
import Vision
import CoreText

enum Advanced {

    // MARK: Compress

    static func compress(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let quality = ctx.int("quality", 1)
        let stem = PDFEngine.stem(input)
        let dest = PDFEngine.output(ctx.outputDir, "\(stem) compressed", "pdf")
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int) ?? 0

        if quality == 0 {
            // Vector-preserving: drop unused objects, keep text selectable.
            try PDFEngine.save(doc, to: dest)
        } else {
            let dpi = CGFloat(ctx.int("dpi", 150))
            let jpegQuality: CGFloat = [0.72, 0.55, 0.35][max(0, min(2, quality - 1))]
            var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []

            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i),
                      let cg = PDFEngine.render(page, dpi: dpi) else { continue }
                let size = PDFEngine.pageSize(page)
                let rep = NSBitmapImageRep(cgImage: cg)
                let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
                let source = jpeg.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
                let compressed = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } ?? cg
                specs.append((size, { context in
                    context.draw(compressed, in: CGRect(origin: .zero, size: size))
                }))
                ctx.progress?(Double(i + 1) / Double(doc.pageCount), "Page \(i + 1) of \(doc.pageCount)")
            }
            guard !specs.isEmpty else { throw fail("No pages could be processed.") }
            let data = try PDFEngine.writePDF(specs)
            try data.write(to: dest)
        }

        let newSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
        if originalSize > 0 && newSize >= originalSize && quality > 0 {
            throw fail("Compression would have made this file larger (\(format(newSize)) vs \(format(originalSize))). The original is already efficient — try the lossless option instead.")
        }
        return [dest]
    }

    static func format(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: OCR

    static func ocr(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let dpi = CGFloat(ctx.int("dpi", 200))
        let searchable = ctx.bool("searchable", true)
        let languages: [String] = {
            let options = ["", "en-US", "hi-IN", "zh-Hans", "es-ES", "fr-FR", "de-DE", "ar-SA"]
            let idx = max(0, min(options.count - 1, ctx.int("lang", 0)))
            return options[idx].isEmpty ? [] : [options[idx]]
        }()

        var allText: [String] = []
        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let cg = PDFEngine.render(page, dpi: dpi) else { continue }
            let size = PDFEngine.pageSize(page)

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if !languages.isEmpty { request.recognitionLanguages = languages }

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([request])
            let observations = (request.results ?? [])

            var pageText: [String] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                pageText.append(candidate.string)
            }
            allText.append(pageText.joined(separator: "\n"))

            if searchable {
                specs.append((size, { context in
                    context.draw(cg, in: CGRect(origin: .zero, size: size))
                    context.setTextDrawingMode(.invisible)
                    for observation in observations {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        let box = observation.boundingBox
                        let rect = CGRect(x: box.minX * size.width,
                                          y: box.minY * size.height,
                                          width: box.width * size.width,
                                          height: box.height * size.height)
                        let fontSize = max(4, rect.height * 0.8)
                        let font = NSFont.systemFont(ofSize: fontSize)
                        let attributed = NSAttributedString(string: candidate.string,
                                                            attributes: [.font: font])
                        let line = CTLineCreateWithAttributedString(attributed)
                        context.textMatrix = .identity
                        context.textPosition = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15)
                        CTLineDraw(line, context)
                    }
                }))
            }
            ctx.progress?(Double(i + 1) / Double(doc.pageCount), "Reading page \(i + 1) of \(doc.pageCount)")
        }

        let joined = allText.joined(separator: "\n\n--- page break ---\n\n")
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw fail("No text was recognised. The scan may be too low-contrast, or set a higher DPI.")
        }

        let stem = PDFEngine.stem(input)
        var written: [URL] = []
        let textURL = PDFEngine.output(ctx.outputDir, "\(stem) ocr", "txt")
        try joined.write(to: textURL, atomically: true, encoding: .utf8)
        written.append(textURL)

        if searchable && !specs.isEmpty {
            let data = try PDFEngine.writePDF(specs)
            let pdfURL = PDFEngine.output(ctx.outputDir, "\(stem) searchable", "pdf")
            try data.write(to: pdfURL)
            written.append(pdfURL)
        }
        return written
    }

    // MARK: Inspect

    static func info(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        guard let doc = PDFDocument(url: input) else { throw fail("Could not open that file.") }
        let size = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int) ?? 0
        var lines: [String] = []
        lines.append("File: \(input.lastPathComponent)")
        lines.append("Size: \(format(size)) (\(size) bytes)")
        lines.append("Pages: \(doc.pageCount)")
        lines.append("Encrypted: \(doc.isEncrypted ? "yes" : "no")")
        lines.append("Locked: \(doc.isLocked ? "yes" : "no")")
        lines.append("")

        lines.append("Metadata")
        if let attrs = doc.documentAttributes, !attrs.isEmpty {
            for key in attrs.keys.sorted(by: { "\($0)" < "\($1)" }) {
                lines.append("  \(key): \(attrs[key] ?? "")")
            }
        } else {
            lines.append("  (none)")
        }
        lines.append("")

        lines.append("Pages")
        for i in 0..<min(doc.pageCount, 200) {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let rotation = page.rotation
            let text = (page.string ?? "").count
            let annotations = page.annotations.count
            lines.append(String(format: "  p%-4d %.0f × %.0f pt   rotation %d°   %d chars   %d annotations",
                                i + 1, box.width, box.height, rotation, text, annotations))
        }
        if doc.pageCount > 200 { lines.append("  … \(doc.pageCount - 200) more") }

        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) info", "txt")
        try lines.joined(separator: "\n").write(to: dest, atomically: true, encoding: .utf8)
        return [dest]
    }

    // MARK: Text diff

    static func compare(_ ctx: RunContext) throws -> [URL] {
        guard ctx.inputs.count >= 2 else { throw fail("Drop exactly two PDFs to compare.") }
        let a = try PDFEngine.open(ctx.inputs[0])
        let b = try PDFEngine.open(ctx.inputs[1])

        func lines(_ doc: PDFDocument) -> [String] {
            (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
                .joined(separator: "\n")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        let left = lines(a), right = lines(b)
        let leftSet = Set(left), rightSet = Set(right)
        let removed = left.filter { !rightSet.contains($0) }
        let added = right.filter { !leftSet.contains($0) }

        var report = "# Text diff\n\n"
        report += "A: \(ctx.inputs[0].lastPathComponent) — \(a.pageCount) pages, \(left.count) lines\n"
        report += "B: \(ctx.inputs[1].lastPathComponent) — \(b.pageCount) pages, \(right.count) lines\n\n"
        report += "Only in A: \(removed.count)\nOnly in B: \(added.count)\n\n"
        if removed.isEmpty && added.isEmpty {
            report += "The text is identical.\n"
        } else {
            report += "## Removed\n\n" + removed.prefix(200).map { "- \($0)" }.joined(separator: "\n") + "\n\n"
            report += "## Added\n\n" + added.prefix(200).map { "+ \($0)" }.joined(separator: "\n") + "\n"
        }

        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(ctx.inputs[0])) diff", "md")
        try report.write(to: dest, atomically: true, encoding: .utf8)
        return [dest]
    }
}
