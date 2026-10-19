import Foundation
import PDFKit
import AppKit
import CoreGraphics

/// Draws a CGPDFPage scaled to fit `rect`, honouring the page's /Rotate entry.
func drawFitted(_ page: CGPDFPage, into rect: CGRect, ctx: CGContext) {
    let media = page.getBoxRect(.mediaBox)
    let angle = ((page.rotationAngle % 360) + 360) % 360
    let swapped = (angle == 90 || angle == 270)
    let visual = swapped ? CGSize(width: media.height, height: media.width) : media.size
    guard visual.width > 0, visual.height > 0 else { return }

    let scale = min(rect.width / visual.width, rect.height / visual.height)
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.scaleBy(x: scale, y: scale)
    ctx.rotate(by: CGFloat(angle) * .pi / 180)
    ctx.translateBy(x: -media.midX, y: -media.midY)
    ctx.drawPDFPage(page)
    ctx.restoreGState()
}

enum Organize {

    // MARK: Merge

    static func merge(_ ctx: RunContext) throws -> [URL] {
        guard ctx.inputs.count >= 2 else { throw fail("Pick at least two PDFs to merge.") }
        let out = PDFDocument()
        for url in ctx.inputs {
            let doc = try PDFEngine.open(url)
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                out.insert(page, at: out.pageCount)
            }
        }
        let name = "\(PDFEngine.stem(ctx.inputs[0])) merged"
        let dest = PDFEngine.output(ctx.outputDir, name, "pdf")
        try PDFEngine.save(out, to: dest)
        return [dest]
    }

    // MARK: Split

    static func split(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let total = doc.pageCount
        var groups: [[Int]] = []

        switch ctx.int("mode") {
        case 1:
            let every = max(1, ctx.int("every", 2))
            var start = 0
            while start < total {
                groups.append(Array(start..<min(start + every, total)))
                start += every
            }
        case 2:
            groups = (0..<total).map { [$0] }
        default:
            let spec = ctx.string("ranges", "1-\(total)")
            for part in spec.split(separator: ",") {
                let piece = part.trimmingCharacters(in: .whitespaces)
                guard !piece.isEmpty else { continue }
                groups.append(try PDFEngine.indices(piece, pageCount: total))
            }
        }

        guard !groups.isEmpty else { throw fail("Nothing to split — check the ranges.") }
        let stem = PDFEngine.stem(input)
        var written: [URL] = []
        for (i, group) in groups.enumerated() {
            let slice = PDFEngine.newDoc(from: doc, pages: group)
            let label = group.count == 1 ? "p\(group[0] + 1)" : "p\(group[0] + 1)-\(group[group.count - 1] + 1)"
            let dest = PDFEngine.output(ctx.outputDir, "\(stem) \(label)", "pdf")
            try PDFEngine.save(slice, to: dest)
            written.append(dest)
            ctx.progress?(Double(i + 1) / Double(groups.count), "Split \(i + 1) of \(groups.count)")
        }
        return written
    }

    // MARK: Extract

    static func extract(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let pages = try PDFEngine.indices(ctx.string("pages", "1"), pageCount: doc.pageCount)
        let out = PDFEngine.newDoc(from: doc, pages: pages)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) extract", "pdf")
        try PDFEngine.save(out, to: dest)
        return [dest]
    }

    // MARK: Remove

    static func remove(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let doomed = Set(try PDFEngine.indices(ctx.string("pages", "1"), pageCount: doc.pageCount))
        let keep = (0..<doc.pageCount).filter { !doomed.contains($0) }
        guard !keep.isEmpty else { throw fail("That would remove every page.") }
        let out = PDFEngine.newDoc(from: doc, pages: keep)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) trimmed", "pdf")
        try PDFEngine.save(out, to: dest)
        return [dest]
    }

    // MARK: Reorder

    static func reorder(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let order = try PDFEngine.indices(ctx.string("order", ""), pageCount: doc.pageCount)
        let out = PDFEngine.newDoc(from: doc, pages: order)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) reordered", "pdf")
        try PDFEngine.save(out, to: dest)
        return [dest]
    }

    // MARK: Rotate

    static func rotate(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let angle = [90, 180, 270][max(0, min(2, ctx.int("angle")))]
        let pages = try PDFEngine.indices(ctx.string("pages", "all"), pageCount: doc.pageCount)
        for idx in pages {
            guard let page = doc.page(at: idx) else { continue }
            page.rotation = ((page.rotation + angle) % 360 + 360) % 360
        }
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) rotated", "pdf")
        try PDFEngine.save(doc, to: dest)
        return [dest]
    }

    // MARK: N-up

    static func nup(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let perSheet = [2, 4, 6, 9][max(0, min(3, ctx.int("perSheet", 1)))]
        let layout: (cols: Int, rows: Int) = [2: (2, 1), 4: (2, 2), 6: (2, 3), 9: (3, 3)][perSheet]!

        guard let firstPage = doc.page(at: 0) else { throw fail("That PDF has no pages.") }
        var sheet = PDFEngine.pageSize(firstPage)
        if layout.cols > layout.rows { sheet = CGSize(width: sheet.height, height: sheet.width) }

        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        var index = 0
        let margin: CGFloat = 12
        let cellW = (sheet.width - margin * CGFloat(layout.cols + 1)) / CGFloat(layout.cols)
        let cellH = (sheet.height - margin * CGFloat(layout.rows + 1)) / CGFloat(layout.rows)

        while index < doc.pageCount {
            let batch = (0..<perSheet).compactMap { doc.page(at: index + $0)?.pageRef }
            specs.append((sheet, { context in
                for (slot, page) in batch.enumerated() {
                    let col = slot % layout.cols
                    let row = slot / layout.cols
                    let rect = CGRect(
                        x: margin + CGFloat(col) * (cellW + margin),
                        y: sheet.height - margin - CGFloat(row + 1) * cellH - CGFloat(row) * margin,
                        width: cellW, height: cellH)
                    drawFitted(page, into: rect, ctx: context)
                }
            }))
            index += perSheet
        }

        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) \(perSheet)-up", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: Overlay

    static func overlay(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        guard let auxURL = ctx.auxFile else { throw fail("Choose the PDF to overlay on top.") }
        let base = try PDFEngine.open(input)
        let top = try PDFEngine.open(auxURL)
        guard top.pageCount > 0 else { throw fail("The overlay PDF has no pages.") }
        let pages = Set(try PDFEngine.indices(ctx.string("pages", "all"), pageCount: base.pageCount))

        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        for i in 0..<base.pageCount {
            guard let page = base.page(at: i) else { continue }
            let size = PDFEngine.pageSize(page)
            specs.append((size, { context in
                if let ref = page.pageRef { drawFitted(ref, into: CGRect(origin: .zero, size: size), ctx: context) }
                guard pages.contains(i),
                      let overlayPage = top.page(at: i % top.pageCount)?.pageRef else { return }
                context.saveGState()
                context.setAlpha(0.9)
                drawFitted(overlayPage, into: CGRect(origin: .zero, size: size), ctx: context)
                context.restoreGState()
            }))
        }

        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) overlaid", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: Scale

    static func scale(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let target = PDFEngine.paperSize(ctx.choice("size", options: ["A4", "US Letter", "A3", "A5", "Legal"]))

        var specs: [(size: CGSize, draw: (CGContext) -> Void)] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let ref = page.pageRef else { continue }
            specs.append((target, { context in
                drawFitted(ref, into: CGRect(origin: .zero, size: target), ctx: context)
            }))
        }
        let data = try PDFEngine.writePDF(specs)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) scaled", "pdf")
        try data.write(to: dest)
        return [dest]
    }

    // MARK: Auto split

    static func autosplit(_ ctx: RunContext) throws -> [URL] {
        let input = try single(ctx)
        let doc = try PDFEngine.open(input)
        let maxPages = max(1, ctx.int("maxPages", 10))
        var written: [URL] = []
        var start = 0
        var part = 1
        while start < doc.pageCount {
            let end = min(start + maxPages, doc.pageCount)
            let slice = PDFEngine.newDoc(from: doc, pages: Array(start..<end))
            let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) part\(part)", "pdf")
            try PDFEngine.save(slice, to: dest)
            written.append(dest)
            start = end
            part += 1
        }
        return written
    }

    // MARK: - Utility

    static func single(_ ctx: RunContext) throws -> URL {
        guard let first = ctx.inputs.first else { throw fail("Choose a PDF first.") }
        return first
    }
}
