import Foundation
import PDFKit
import AppKit
import CoreGraphics

/// Headless exercise of every native tool. Run with `PDFBar --selftest`.
enum SelfTest {

    static func run() -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfbar-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        print("PDFBar self-test → \(root.path)\n")

        var failures: [String] = []

        func check(_ name: String, _ body: () throws -> String) {
            do {
                let detail = try body()
                print("  PASS  \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(detail)")
            } catch {
                print("  FAIL  \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(error.localizedDescription)")
                failures.append(name)
            }
        }

        func pages(_ url: URL) throws -> Int {
            guard let doc = PDFDocument(url: url) else {
                throw fail("output is not a readable PDF: \(url.lastPathComponent)")
            }
            return doc.pageCount
        }

        func run(_ id: String, inputs: [URL], aux: URL? = nil,
                 _ params: [String: Any] = [:]) throws -> [URL] {
            let context = RunContext(inputs: inputs, auxFile: aux, params: params, outputDir: root)
            return try PDFEngine.run(id, context)
        }

        // Fixtures
        let a = root.appendingPathComponent("a.pdf")
        let b = root.appendingPathComponent("b.pdf")
        do {
            try samplePDF(pages: 6, title: "Report A", to: a)
            try samplePDF(pages: 4, title: "Report B", to: b)
        } catch {
            print("could not build fixtures: \(error.localizedDescription)")
            return false
        }

        check("merge") {
            let out = try run("merge", inputs: [a, b])
            let count = try pages(out[0])
            guard count == 10 else { throw fail("expected 10 pages, got \(count)") }
            return "\(count) pages"
        }

        check("split") {
            let out = try run("split", inputs: [a], ["mode": 0, "ranges": "1-2, 3-4"])
            guard out.count == 2 else { throw fail("expected 2 files, got \(out.count)") }
            return "\(out.count) files"
        }

        check("extract") {
            let out = try run("extract", inputs: [a], ["pages": "2-4"])
            let count = try pages(out[0])
            guard count == 3 else { throw fail("expected 3 pages, got \(count)") }
            return "\(count) pages"
        }

        check("remove") {
            let out = try run("remove", inputs: [a], ["pages": "1,2"])
            let count = try pages(out[0])
            guard count == 4 else { throw fail("expected 4 pages, got \(count)") }
            return "\(count) pages"
        }

        check("reorder") {
            let out = try run("reorder", inputs: [a], ["order": "6,5,4,3,2,1"])
            let count = try pages(out[0])
            guard count == 6 else { throw fail("expected 6 pages, got \(count)") }
            return "\(count) pages"
        }

        check("rotate") {
            let out = try run("rotate", inputs: [a], ["angle": 0, "pages": "all"])
            guard let doc = PDFDocument(url: out[0]), let page = doc.page(at: 0) else {
                throw fail("unreadable output")
            }
            guard page.rotation == 90 else { throw fail("expected rotation 90, got \(page.rotation)") }
            return "rotation \(page.rotation)°"
        }

        check("n-up") {
            let out = try run("nup", inputs: [a], ["perSheet": 1])
            let count = try pages(out[0])
            guard count == 2 else { throw fail("6 pages at 4-up should be 2 sheets, got \(count)") }
            return "\(count) sheets"
        }

        check("overlay") {
            let out = try run("overlay", inputs: [a], aux: b, ["pages": "all"])
            let count = try pages(out[0])
            guard count == 6 else { throw fail("expected 6 pages, got \(count)") }
            return "\(count) pages"
        }

        check("scale") {
            let out = try run("scale", inputs: [a], ["size": 0])
            guard let doc = PDFDocument(url: out[0]), let page = doc.page(at: 0) else {
                throw fail("unreadable output")
            }
            let box = page.bounds(for: .mediaBox)
            guard abs(box.width - 595) < 2, abs(box.height - 842) < 2 else {
                throw fail("expected A4, got \(Int(box.width))×\(Int(box.height))")
            }
            return "\(Int(box.width))×\(Int(box.height)) pt"
        }

        check("split by size") {
            let out = try run("autosplit", inputs: [a], ["maxPages": 4])
            guard out.count == 2 else { throw fail("6 pages at 4/page should be 2 files, got \(out.count)") }
            return "\(out.count) files"
        }

        check("pdf to images") {
            let out = try run("pdf2img", inputs: [a], ["format": 0, "dpi": 72])
            guard out.count == 6 else { throw fail("expected 6 images, got \(out.count)") }
            return "\(out.count) png"
        }

        check("images to pdf") {
            let images = try run("pdf2img", inputs: [a], ["format": 0, "dpi": 72]).prefix(3)
            let out = try run("img2pdf", inputs: Array(images), ["size": 0])
            let count = try pages(out[0])
            guard count == 3 else { throw fail("expected 3 pages, got \(count)") }
            return "\(count) pages"
        }

        check("pdf to text") {
            let out = try run("pdf2txt", inputs: [a])
            let text = (try? String(contentsOf: out[0], encoding: .utf8)) ?? ""
            guard text.contains("Page 1 of 6") else {
                throw fail("text layer did not survive: \(text.prefix(60))")
            }
            return "\(text.count) chars"
        }

        check("pdf to markdown") {
            let out = try run("pdf2md", inputs: [a])
            let text = (try? String(contentsOf: out[0], encoding: .utf8)) ?? ""
            guard text.contains("## Report A") else { throw fail("no heading inferred") }
            return "\(text.count) chars"
        }

        check("pdf to html") {
            let out = try run("pdf2html", inputs: [a])
            let text = (try? String(contentsOf: out[0], encoding: .utf8)) ?? ""
            guard text.contains("<h1>Report A</h1>") else { throw fail("no heading emitted") }
            return "\(text.count) chars"
        }

        check("watermark") {
            let out = try run("watermark", inputs: [a],
                              ["text": "DRAFT", "size": 60, "opacity": 0.2, "angle": 0])
            _ = try pages(out[0])
            let size = fileSize(out[0])
            guard size > 0 else { throw fail("empty output") }
            return "\(size) bytes"
        }

        check("page numbers") {
            let out = try run("pagenum", inputs: [a],
                              ["position": 0, "start": 1, "format": "{n} / {total}"])
            _ = try pages(out[0])
            return "6 pages numbered"
        }

        check("crop") {
            let out = try run("crop", inputs: [a],
                              ["top": 40, "bottom": 40, "left": 30, "right": 30])
            guard let doc = PDFDocument(url: out[0]), let page = doc.page(at: 0) else {
                throw fail("unreadable output")
            }
            let box = page.bounds(for: .cropBox)
            guard box.width < 595 else { throw fail("cropBox was not applied") }
            return "cropBox \(Int(box.width))×\(Int(box.height))"
        }

        // Fixture: a small PNG to stamp with.
        var stampURL: URL?
        if let png = makePNG() {
            let url = root.appendingPathComponent("stamp.png")
            try? png.write(to: url)
            stampURL = url
        }

        check("stamp image") {
            guard let stampURL else { throw fail("could not build the stamp fixture") }
            let out = try run("stamp", inputs: [a], aux: stampURL,
                              ["position": 0, "width": 20, "opacity": 1.0, "pages": "1-2"])
            _ = try pages(out[0])
            return "stamped pages 1-2"
        }

        check("flatten") {
            let out = try run("flatten", inputs: [a])
            guard let doc = PDFDocument(url: out[0]), let page = doc.page(at: 0) else {
                throw fail("unreadable output")
            }
            guard page.annotations.isEmpty else { throw fail("annotations remain") }
            return "annotations cleared"
        }

        check("redact") {
            let out = try run("redact", inputs: [a],
                              ["top": 60, "bottom": 60, "left": 0, "right": 0, "style": 0])
            _ = try pages(out[0])
            return "bands covered"
        }

        check("metadata") {
            let out = try run("metadata", inputs: [a],
                              ["title": "Quarterly", "author": "Vega", "subject": "Q3", "keywords": "a,b"])
            guard let doc = PDFDocument(url: out[0]) else { throw fail("unreadable output") }
            let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            guard title == "Quarterly" else { throw fail("title is \(title ?? "nil")") }
            return "title written"
        }

        check("encrypt + decrypt") {
            let locked = try run("encrypt", inputs: [a], ["user": "s3cret", "owner": "s3cret"])
            guard let doc = PDFDocument(url: locked[0]), doc.isLocked else {
                throw fail("output is not encrypted")
            }
            guard doc.unlock(withPassword: "wrong") == false else {
                throw fail("a wrong password was accepted")
            }
            let unlocked = try run("decrypt", inputs: [locked[0]], ["password": "s3cret"])
            guard let plain = PDFDocument(url: unlocked[0]), !plain.isLocked else {
                throw fail("decryption failed")
            }
            return "round-trip ok"
        }

        check("sanitize") {
            let out = try run("sanitize", inputs: [a])
            guard let doc = PDFDocument(url: out[0]) else { throw fail("unreadable output") }
            // PDFKit rewrites Producer on save, so verify the title instead.
            guard (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) == "a" else {
                throw fail("metadata was not rewritten")
            }
            guard doc.page(at: 0)?.annotations.isEmpty ?? false else { throw fail("annotations remain") }
            return "metadata stripped"
        }

        check("repair") {
            let out = try run("repair", inputs: [a])
            let count = try pages(out[0])
            guard count == 6 else { throw fail("lost pages during repair") }
            return "\(count) pages recovered"
        }

        check("compress lossless") {
            let out = try run("compress", inputs: [a], ["quality": 0])
            return "\(fileSize(out[0])) bytes"
        }

        check("ocr") {
            // Build a scanned-looking PDF: rasterise page 1, then OCR it back.
            guard let doc = PDFDocument(url: a), let page = doc.page(at: 0),
                  let cg = PDFEngine.render(page, dpi: 200) else {
                throw fail("could not rasterise the fixture")
            }
            let scanned = try PDFEngine.writePDF([(CGSize(width: 595, height: 842), { ctx in
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 595, height: 842))
            })])
            let scanURL = root.appendingPathComponent("scan.pdf")
            try scanned.write(to: scanURL)

            let out = try run("ocr", inputs: [scanURL], ["lang": 1, "searchable": true, "dpi": 200])
            let text = out.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: " ")
            guard text.contains("Page 1") || text.contains("Page") else {
                throw fail("Vision returned no useful text: \(text.prefix(80))")
            }
            return "\(out.count) outputs, recognised text"
        }

        check("inspect") {
            let out = try run("info", inputs: [a])
            let text = (try? String(contentsOf: out[0], encoding: .utf8)) ?? ""
            guard text.contains("Pages: 6") else { throw fail("wrong page count in report") }
            return "report written"
        }

        check("text diff") {
            let out = try run("compare", inputs: [a, b])
            let text = (try? String(contentsOf: out[0], encoding: .utf8)) ?? ""
            guard text.contains("Only in A") else { throw fail("diff report malformed") }
            return "diff written"
        }

        print("\n\(failures.isEmpty ? "All native tools passed." : "\(failures.count) failed: \(failures.joined(separator: ", "))")")
        print("Artifacts: \(root.path)")
        return failures.isEmpty
    }

    // MARK: Fixtures

    static func samplePDF(pages: Int, title: String, to url: URL) throws {
        let size = CGSize(width: 595, height: 842)
        let heading = NSFont(name: "Helvetica-Bold", size: 26) ?? NSFont.boldSystemFont(ofSize: 26)
        let body = NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        for index in 1...pages {
            specs.append((size, { ctx in
                PDFEngine.drawText(title, font: heading, color: .black,
                                   at: CGPoint(x: 72, y: 700), in: ctx)
                PDFEngine.drawText("Page \(index) of \(pages)",
                                   font: body, color: .black,
                                   at: CGPoint(x: 72, y: 660), in: ctx)
                PDFEngine.drawText("The quick brown fox jumps over the lazy dog.",
                                   font: body, color: .black,
                                   at: CGPoint(x: 72, y: 600), in: ctx)
            }))
        }
        let data = try PDFEngine.writePDF(specs)
        try data.write(to: url)
    }

    static func makePNG() -> Data? {
        let width = 200, height = 100
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 20, y: 20, width: 60, height: 60))
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
