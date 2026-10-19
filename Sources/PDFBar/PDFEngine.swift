import Foundation
import PDFKit
import AppKit
import CoreGraphics

// MARK: - Shared helpers

enum PDFEngine {

    // MARK: Dispatch

    static func run(_ toolID: String, _ ctx: RunContext) throws -> [URL] {
        switch toolID {
        case "merge":       return try Organize.merge(ctx)
        case "split":       return try Organize.split(ctx)
        case "extract":     return try Organize.extract(ctx)
        case "remove":      return try Organize.remove(ctx)
        case "reorder":     return try Organize.reorder(ctx)
        case "rotate":      return try Organize.rotate(ctx)
        case "nup":         return try Organize.nup(ctx)
        case "overlay":     return try Organize.overlay(ctx)
        case "scale":       return try Organize.scale(ctx)
        case "autosplit":   return try Organize.autosplit(ctx)

        case "pdf2img":     return try Convert.pdfToImages(ctx)
        case "img2pdf":     return try Convert.imagesToPDF(ctx)
        case "pdf2txt":     return try Convert.pdfToText(ctx)
        case "pdf2md":      return try Convert.pdfToMarkdown(ctx)
        case "pdf2html":    return try Convert.pdfToHTML(ctx)
        case "html2pdf":    return try Convert.htmlToPDF(ctx)
        case "url2pdf":     return try Convert.urlToPDF(ctx)

        case "watermark":   return try Edit.watermark(ctx)
        case "pagenum":     return try Edit.pageNumbers(ctx)
        case "crop":        return try Edit.crop(ctx)
        case "stamp":       return try Edit.stamp(ctx)
        case "flatten":     return try Edit.flatten(ctx)
        case "redact":      return try Edit.redact(ctx)
        case "metadata":    return try Edit.metadata(ctx)

        case "encrypt":     return try Security.encrypt(ctx)
        case "decrypt":     return try Security.decrypt(ctx)
        case "sanitize":    return try Security.sanitize(ctx)
        case "repair":      return try Security.repair(ctx)

        case "compress":    return try Advanced.compress(ctx)
        case "ocr":         return try Advanced.ocr(ctx)
        case "info":        return try Advanced.info(ctx)
        case "compare":     return try Advanced.compare(ctx)

        default:
            throw fail("\(toolID) runs on the Stirling server, not the native engine.")
        }
    }

    // MARK: - Document helpers

    static func open(_ url: URL, password: String = "") throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else {
            throw fail("Could not open \(url.lastPathComponent). It may be damaged or password-protected.")
        }
        if doc.isLocked {
            guard doc.unlock(withPassword: password) else {
                throw fail("\(url.lastPathComponent) is password-protected. Supply the password.")
            }
        }
        return doc
    }

    /// Parses "1-3,5,9-" into 0-based page indices, clamped to the document.
    /// An empty spec means "all pages".
    static func indices(_ spec: String, pageCount: Int) throws -> [Int] {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "all" || trimmed == "*" {
            return Array(0..<pageCount)
        }
        var result: [Int] = []
        for raw in trimmed.split(separator: ",") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { continue }
            if part.contains("-") {
                let sides = part.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                let startText = sides[0].trimmingCharacters(in: .whitespaces)
                let endText = sides.count > 1 ? sides[1].trimmingCharacters(in: .whitespaces) : ""
                guard let start = Int(startText.isEmpty ? "1" : startText) else {
                    throw fail("Could not read the page range \"\(part)\".")
                }
                let end = endText.isEmpty ? pageCount : (Int(endText) ?? pageCount)
                guard start >= 1, end >= start else {
                    throw fail("Page range \"\(part)\" is not valid.")
                }
                for p in start...min(end, pageCount) where p <= pageCount {
                    result.append(p - 1)
                }
            } else if let p = Int(part) {
                if p >= 1 && p <= pageCount { result.append(p - 1) }
            } else {
                throw fail("Could not read \"\(part)\" as a page number.")
            }
        }
        if result.isEmpty { throw fail("That page selection is outside the document (1–\(pageCount)).") }
        return result
    }

    static func newDoc(from source: PDFDocument, pages: [Int]) -> PDFDocument {
        let out = PDFDocument()
        for idx in pages {
            guard let page = source.page(at: idx) else { continue }
            out.insert(page, at: out.pageCount)
        }
        return out
    }

    static func save(_ doc: PDFDocument, to url: URL) throws {
        guard doc.write(to: url) else { throw fail("Could not write \(url.lastPathComponent).") }
    }

    /// Returns a non-colliding URL in `dir`, e.g. "report (2).pdf".
    static func output(_ dir: URL, _ base: String, _ ext: String) -> URL {
        let clean = base.replacingOccurrences(of: "/", with: "-")
        var candidate = dir.appendingPathComponent("\(clean).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(clean) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    static func stem(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Rasterising

    static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        guard let cgPage = page.pageRef else { return nil }
        let box = cgPage.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = max(dpi, 18) / 72.0
        let w = Int((box.width * scale).rounded())
        let h = Int((box.height * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        ctx.drawPDFPage(cgPage)
        return ctx.makeImage()
    }

    static func pageSize(_ page: PDFPage) -> CGSize {
        if let ref = page.pageRef {
            let box = ref.getBoxRect(.mediaBox)
            if box.width > 0 && box.height > 0 { return box.size }
        }
        return page.bounds(for: .mediaBox).size
    }

    // MARK: - PDF writing context

    /// Builds a PDF by letting the caller draw each page into a fresh context.
    /// Content drawn with `drawPDFPage` stays vector — text remains selectable.
    static func writePDF(_ pages: [(size: CGSize, draw: (CGContext) -> Void)]) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw fail("Could not allocate a PDF writer.")
        }
        var initialBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &initialBox, nil) else {
            throw fail("Could not create a PDF context.")
        }
        for spec in pages {
            var box = CGRect(origin: .zero, size: spec.size)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            let info: [String: Any] = [
                kCGPDFContextMediaBox as String: boxData,
                kCGPDFContextCropBox as String: boxData
            ]
            ctx.beginPDFPage(info as CFDictionary)
            spec.draw(ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    // MARK: - Text drawing

    static func drawText(_ text: String, font: NSFont, color: NSColor,
                         at point: CGPoint, in ctx: CGContext, rotate: CGFloat = 0) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        ctx.saveGState()
        if rotate != 0 {
            ctx.translateBy(x: point.x, y: point.y)
            ctx.rotate(by: rotate)
            ctx.translateBy(x: -point.x, y: -point.y)
        }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        attributed.draw(at: point)
        NSGraphicsContext.current = previous
        ctx.restoreGState()
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: - Images

    static func loadImage(_ url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url),
           let page = doc.page(at: 0) {
            return NSImage(cgImage: render(page, dpi: 200)!, size: pageSize(page))
        }
        return NSImage(contentsOf: url)
    }

    static func paperSize(_ name: String) -> CGSize {
        switch name {
        case "A3":        return CGSize(width: 842, height: 1191)
        case "A4":        return CGSize(width: 595, height: 842)
        case "A5":        return CGSize(width: 420, height: 595)
        case "Legal":     return CGSize(width: 612, height: 1008)
        case "US Letter": return CGSize(width: 612, height: 792)
        default:          return CGSize(width: 595, height: 842)
        }
    }
}
