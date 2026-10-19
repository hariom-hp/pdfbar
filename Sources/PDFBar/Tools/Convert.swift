import Foundation
import PDFKit
import AppKit
import WebKit

enum Convert {

    // MARK: PDF -> images

    static func pdfToImages(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let formats = ["png", "jpeg", "tiff"]
        let format = formats[max(0, min(2, ctx.int("format")))]
        let dpi = CGFloat(ctx.int("dpi", 150))
        let stem = PDFEngine.stem(input)
        var written: [URL] = []

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let cg = PDFEngine.render(page, dpi: dpi) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            let data: Data?
            switch format {
            case "jpeg": data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            case "tiff": data = rep.representation(using: .tiff, properties: [:])
            default:     data = rep.representation(using: .png, properties: [:])
            }
            guard let data else { continue }
            let dest = PDFEngine.output(ctx.outputDir, "\(stem) page\(i + 1)", format == "jpeg" ? "jpg" : format)
            try data.write(to: dest)
            written.append(dest)
            ctx.progress?(Double(i + 1) / Double(doc.pageCount), "Page \(i + 1) of \(doc.pageCount)")
        }
        guard !written.isEmpty else { throw fail("No pages could be rendered.") }
        return written
    }

    // MARK: Images -> PDF

    static func imagesToPDF(_ ctx: RunContext) throws -> [URL] {
        guard !ctx.inputs.isEmpty else { throw fail("Drop some images first.") }
        let fitMode = ctx.int("size", 0)
        let paper = PDFEngine.paperSize("A4")
        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []

        for url in ctx.inputs {
            guard let image = NSImage(contentsOf: url),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let natural = CGSize(width: cg.width, height: cg.height)
            let target: CGSize = fitMode == 0 ? natural : paper
            specs.append((target, { context in
                let scale = min(target.width / natural.width, target.height / natural.height)
                let w = natural.width * scale, h = natural.height * scale
                let rect = CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h)
                context.draw(cg, in: rect)
            }))
        }
        guard !specs.isEmpty else { throw fail("None of those files could be read as images.") }
        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(ctx.inputs[0])) images", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: PDF -> text

    static func pdfToText(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        var parts: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            parts.append(page.string ?? "")
        }
        let text = parts.joined(separator: "\n\n--- page break ---\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw fail("This PDF has no text layer — it is probably a scan. Run OCR instead.")
        }
        let dest = PDFEngine.output(ctx.outputDir, PDFEngine.stem(input), "txt")
        try text.write(to: dest, atomically: true, encoding: .utf8)
        return [dest]
    }

    // MARK: PDF -> Markdown

    static func pdfToMarkdown(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let blocks = textBlocks(doc)
        guard !blocks.isEmpty else { throw fail("No text layer found. Run OCR first.") }

        // Body size = the most common rounded font size.
        var histogram: [Int: Int] = [:]
        for block in blocks { histogram[block.size, default: 0] += block.text.count }
        let bodySize = histogram.max { $0.value < $1.value }?.key ?? 12

        var out = "# \(doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? PDFEngine.stem(input))\n\n"
        for block in blocks {
            let line = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if block.size >= bodySize + 8 {
                out += "## \(line)\n\n"
            } else if block.size >= bodySize + 3 {
                out += "### \(line)\n\n"
            } else if block.size <= bodySize - 2 {
                out += "> \(line)\n\n"
            } else {
                out += "\(line)\n\n"
            }
        }
        let dest = PDFEngine.output(ctx.outputDir, PDFEngine.stem(input), "md")
        try out.write(to: dest, atomically: true, encoding: .utf8)
        return [dest]
    }

    // MARK: PDF -> HTML

    static func pdfToHTML(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let blocks = textBlocks(doc)
        guard !blocks.isEmpty else { throw fail("No text layer found. Run OCR first.") }

        var histogram: [Int: Int] = [:]
        for block in blocks { histogram[block.size, default: 0] += block.text.count }
        let bodySize = histogram.max { $0.value < $1.value }?.key ?? 12

        var body = ""
        for block in blocks {
            let line = escape(block.text.trimmingCharacters(in: .whitespacesAndNewlines))
            if line.isEmpty { continue }
            if block.size >= bodySize + 8 {
                body += "<h1>\(line)</h1>\n"
            } else if block.size >= bodySize + 3 {
                body += "<h2>\(line)</h2>\n"
            } else {
                body += "<p>\(line)</p>\n"
            }
        }
        let title = escape(PDFEngine.stem(input))
        let html = """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;max-width:42em;margin:3em auto;padding:0 1.2em;color:#1a1a1a}
        h1{font-size:1.8em}h2{font-size:1.4em}p{margin:0 0 1em}</style></head>
        <body>\n\(body)</body></html>
        """
        let dest = PDFEngine.output(ctx.outputDir, PDFEngine.stem(input), "html")
        try html.write(to: dest, atomically: true, encoding: .utf8)
        return [dest]
    }

    // MARK: HTML -> PDF

    static func htmlToPDF(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let paper = PDFEngine.paperSize(ctx.choice("size", options: ["A4", "US Letter"]))
        let data = try WebRenderer.render(request: URLRequest(url: input), paper: paper)
        let dest = PDFEngine.output(ctx.outputDir, PDFEngine.stem(input), "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: URL -> PDF

    static func urlToPDF(_ ctx: RunContext) throws -> [URL] {
        var raw = ctx.string("url").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw fail("Enter a URL.") }
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        guard let url = URL(string: raw), url.host != nil else { throw fail("\"\(raw)\" is not a valid URL.") }
        let paper = PDFEngine.paperSize(ctx.choice("size", options: ["A4", "US Letter"]))
        let data = try WebRenderer.render(request: URLRequest(url: url), paper: paper)
        let host = url.host ?? "page"
        let dest = PDFEngine.output(ctx.outputDir, host, "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: - Text block extraction

    struct Block {
        let text: String
        let size: Int
    }

    /// Groups the document's attributed text into paragraph-ish blocks with a font size.
    static func textBlocks(_ doc: PDFDocument) -> [Block] {
        var blocks: [Block] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            guard let attributed = page.attributedString, attributed.length > 0 else {
                if let plain = page.string, !plain.isEmpty {
                    blocks.append(Block(text: plain, size: 12))
                }
                continue
            }
            let ns = attributed.string as NSString
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                let font = attrs[.font] as? NSFont
                let size = Int((font?.pointSize ?? 12).rounded())
                let piece = ns.substring(with: range)
                for line in piece.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { continue }
                    if let last = blocks.last, last.size == size, last.text.count < 400 {
                        blocks[blocks.count - 1] = Block(text: last.text + " " + trimmed, size: size)
                    } else {
                        blocks.append(Block(text: trimmed, size: size))
                    }
                }
            }
        }
        return blocks
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Headless web rendering

enum WebRenderer {
    private final class Loader: NSObject, WKNavigationDelegate {
        let onFinish: (Error?) -> Void
        init(_ onFinish: @escaping (Error?) -> Void) { self.onFinish = onFinish }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish(nil) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFinish(error) }
    }

    /// Loads a URL in an offscreen WKWebView and prints it to PDF.
    /// Safe to call from any thread; WebKit work is marshalled to the main queue.
    static func render(request: URLRequest, paper: CGSize) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var output: Data?
        var failure: Error?

        let work = {
            let web = WKWebView(frame: CGRect(origin: .zero, size: paper))
            let loader = Loader { error in
                if let error {
                    failure = error
                    semaphore.signal()
                    return
                }
                let config = WKPDFConfiguration()
                config.rect = CGRect(origin: .zero, size: paper)
                web.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let data): output = data
                    case .failure(let error): failure = error
                    }
                    semaphore.signal()
                }
            }
            objc_setAssociatedObject(web, &WebRenderer.assocKey, loader, .OBJC_ASSOCIATION_RETAIN)
            web.navigationDelegate = loader
            web.load(request)
        }

        if Thread.isMainThread {
            DispatchQueue.main.async(execute: work)
            let deadline = Date().addingTimeInterval(30)
            while semaphore.wait(timeout: .now()) == .timedOut {
                if Date() > deadline { throw fail("Timed out loading the page.") }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        } else {
            DispatchQueue.main.async(execute: work)
            if semaphore.wait(timeout: .now() + 30) == .timedOut {
                throw fail("Timed out loading the page.")
            }
        }

        if let failure { throw fail("Could not load the page: \(failure.localizedDescription)") }
        guard let output, !output.isEmpty else { throw fail("The page produced an empty PDF.") }
        return output
    }

    private static var assocKey: UInt8 = 0
}
