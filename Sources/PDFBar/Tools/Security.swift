import Foundation
import PDFKit

enum Security {

    // MARK: Encrypt

    static func encrypt(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let user = ctx.string("user").trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty else { throw fail("An open password is required.") }
        var owner = ctx.string("owner").trimmingCharacters(in: .whitespaces)
        if owner.isEmpty { owner = user }

        let doc = try PDFEngine.open(input)
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) locked", "pdf")
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: user,
            .ownerPasswordOption: owner
        ]
        guard doc.write(to: dest, withOptions: options) else {
            throw fail("Could not write the encrypted file.")
        }
        return [dest]
    }

    // MARK: Decrypt

    static func decrypt(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        guard let doc = PDFDocument(url: input) else {
            throw fail("Could not open \(input.lastPathComponent).")
        }
        if doc.isLocked {
            let password = ctx.string("password")
            guard doc.unlock(withPassword: password) else {
                throw fail("That password did not work.")
            }
        }
        // PDFKit carries the encryption dictionary over when you re-save the same
        // document, so rebuild it page by page to guarantee a plain file.
        let plain = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            plain.insert(page, at: plain.pageCount)
        }
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) unlocked", "pdf")
        try PDFEngine.save(plain, to: dest)
        return [dest]
    }

    // MARK: Sanitize

    static func sanitize(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        let doc = try PDFEngine.open(input)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for annotation in page.annotations { page.removeAnnotation(annotation) }
        }
        doc.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: PDFEngine.stem(input),
            PDFDocumentAttribute.producerAttribute: "PDFBar"
        ]
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) sanitized", "pdf")
        try PDFEngine.save(doc, to: dest)
        return [dest]
    }

    // MARK: Repair

    static func repair(_ ctx: RunContext) throws -> [URL] {
        let input = try Organize.single(ctx)
        guard let doc = PDFDocument(url: input) else {
            throw fail("The file is too damaged to parse at all.")
        }
        if doc.isLocked { _ = doc.unlock(withPassword: ctx.string("password")) }
        guard doc.pageCount > 0 else { throw fail("No readable pages were recovered.") }
        let dest = PDFEngine.output(ctx.outputDir, "\(PDFEngine.stem(input)) repaired", "pdf")
        try PDFEngine.save(doc, to: dest)
        return [dest]
    }
}
