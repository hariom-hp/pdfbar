import Foundation
import PDFKit
import AppKit
import CoreGraphics

enum Edit {

    // MARK: Watermark

    static func watermark(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let text = ctx.string("text", "CONFIDENTIAL")
        guard !text.isEmpty else { throw fail("Enter the watermark text.") }
        let fontSize = CGFloat(max(6, ctx.int("size", 60)))
        let opacity = CGFloat(ctx.double("opacity", 0.15))
        let mode = ctx.int("angle")
        // Public font faces embed cleanly into a PDF; the private system UI font
        // falls back to Times when CoreText tries to subset it.
        let font = NSFont(name: "Helvetica-Bold", size: fontSize)
            ?? NSFont.boldSystemFont(ofSize: fontSize)
        let color = NSColor(calibratedWhite: 0.4, alpha: opacity)

        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let ref = page.pageRef else { continue }
            let size = PDFEngine.pageSize(page)
            specs.append((size, { context in
                drawFitted(ref, into: CGRect(origin: .zero, size: size), ctx: context)
                let width = PDFEngine.textWidth(text, font: font)
                switch mode {
                case 1:
                    PDFEngine.drawText(text, font: font, color: color,
                                       at: CGPoint(x: (size.width - width) / 2, y: size.height / 2),
                                       in: context)
                case 2:
                    PDFEngine.drawText(text, font: font, color: color,
                                       at: CGPoint(x: size.width / 2, y: (size.height - width) / 2),
                                       in: context, rotate: .pi / 2)
                default:
                    let angle: CGFloat = -45 * .pi / 180
                    PDFEngine.drawText(text, font: font, color: color,
                                       at: CGPoint(x: size.width * 0.12, y: size.height * 0.28),
                                       in: context, rotate: angle)
                }
            }))
        }
        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) watermarked", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: Page numbers

    static func pageNumbers(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let format = ctx.string("format", "{n} / {total}")
        let start = ctx.int("start", 1)
        let position = ctx.int("position")
        let total = doc.pageCount
        let font = NSFont(name: "Helvetica", size: 10) ?? NSFont.systemFont(ofSize: 10)
        let color = NSColor(calibratedWhite: 0.25, alpha: 1)

        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        for i in 0..<total {
            guard let page = doc.page(at: i), let ref = page.pageRef else { continue }
            let size = PDFEngine.pageSize(page)
            let label = format
                .replacingOccurrences(of: "{n}", with: "\(i + start)")
                .replacingOccurrences(of: "{total}", with: "\(total + start - 1)")
            specs.append((size, { context in
                drawFitted(ref, into: CGRect(origin: .zero, size: size), ctx: context)
                let width = PDFEngine.textWidth(label, font: font)
                let margin: CGFloat = 28
                var point: CGPoint
                switch position {
                case 1: point = CGPoint(x: size.width - width - margin, y: margin)
                case 2: point = CGPoint(x: size.width - width - margin, y: size.height - margin - 12)
                case 3: point = CGPoint(x: margin, y: margin)
                default: point = CGPoint(x: (size.width - width) / 2, y: margin)
                }
                PDFEngine.drawText(label, font: font, color: color, at: point, in: context)
            }))
        }
        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) numbered", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: Crop

    static func crop(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let top = CGFloat(ctx.int("top", 0))
        let bottom = CGFloat(ctx.int("bottom", 0))
        let left = CGFloat(ctx.int("left", 0))
        let right = CGFloat(ctx.int("right", 0))

        var changed = false
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let media = page.bounds(for: .mediaBox)
            let inset = CGRect(x: media.minX + left,
                               y: media.minY + bottom,
                               width: media.width - left - right,
                               height: media.height - top - bottom)
            guard inset.width > 20, inset.height > 20 else {
                throw fail("Those margins are larger than the page itself.")
            }
            page.setBounds(inset, for: .cropBox)
            changed = true
        }
        guard changed else { throw fail("That PDF has no pages.") }
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) cropped", "pdf")
        try PDFEngine.save(doc, to: dest)
        return [dest]
    }

    // MARK: Stamp image

    static func stamp(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        guard let aux = ctx.auxFile else { throw fail("Choose the image to stamp.") }
        guard let image = PDFEngine.loadImage(aux),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw fail("Could not read that image.")
        }
        let doc = try PDFEngine.open(input)
        let pages = Set(try PDFEngine.indices(ctx.string("pages", "all"), pageCount: doc.pageCount))
        let pct = CGFloat(max(2, min(100, ctx.int("width", 25)))) / 100
        let opacity = CGFloat(ctx.double("opacity", 1.0))
        let position = ctx.int("position")

        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let ref = page.pageRef else { continue }
            let size = PDFEngine.pageSize(page)
            specs.append((size, { context in
                drawFitted(ref, into: CGRect(origin: .zero, size: size), ctx: context)
                guard pages.contains(i) else { return }
                let targetW = size.width * pct
                let targetH = targetW * CGFloat(cg.height) / CGFloat(cg.width)
                let margin: CGFloat = 24
                var origin: CGPoint
                switch position {
                case 1: origin = CGPoint(x: margin, y: margin)
                case 2: origin = CGPoint(x: size.width - targetW - margin, y: size.height - targetH - margin)
                case 3: origin = CGPoint(x: margin, y: size.height - targetH - margin)
                case 4: origin = CGPoint(x: (size.width - targetW) / 2, y: (size.height - targetH) / 2)
                default: origin = CGPoint(x: size.width - targetW - margin, y: margin)
                }
                context.saveGState()
                context.setAlpha(opacity)
                context.draw(cg, in: CGRect(origin: origin, size: CGSize(width: targetW, height: targetH)))
                context.restoreGState()
            }))
        }
        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) stamped", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: Flatten

    static func flatten(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for annotation in page.annotations { page.removeAnnotation(annotation) }
        }
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) flattened", "pdf")
        try PDFEngine.save(doc, to: dest)
        return [dest]
    }

    // MARK: Redact

    static func redact(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        let top = CGFloat(ctx.int("top", 0))
        let bottom = CGFloat(ctx.int("bottom", 0))
        let left = CGFloat(ctx.int("left", 0))
        let right = CGFloat(ctx.int("right", 0))
        guard top + bottom + left + right > 0 else { throw fail("Set at least one band to cover.") }
        let fill = ctx.int("style") == 1
            ? CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            : CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let cgPage = PDFEngine.render(page, dpi: 200) else { continue }
            let size = PDFEngine.pageSize(page)
            specs.append((size, { context in
                context.draw(cgPage, in: CGRect(origin: .zero, size: size))
                context.setFillColor(fill)
                let bands = [
                    CGRect(x: 0, y: size.height - top, width: size.width, height: top),
                    CGRect(x: 0, y: 0, width: size.width, height: bottom),
                    CGRect(x: 0, y: 0, width: left, height: size.height),
                    CGRect(x: size.width - right, y: 0, width: right, height: size.height)
                ]
                for band in bands where band.width > 0 && band.height > 0 {
                    context.fill(band)
                }
            }))
        }
        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) redacted", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: Metadata

    static func metadata(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        var attrs = doc.documentAttributes ?? [:]
        func apply(_ key: PDFDocumentAttribute, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { attrs[key] = trimmed }
        }
        apply(.titleAttribute, ctx.string("title"))
        apply(.authorAttribute, ctx.string("author"))
        apply(.subjectAttribute, ctx.string("subject"))
        apply(.keywordsAttribute, ctx.string("keywords"))
        doc.documentAttributes = attrs
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) metadata", "pdf")
        try PDFEngine.save(doc, to: dest)
        return [dest]
    }
}
