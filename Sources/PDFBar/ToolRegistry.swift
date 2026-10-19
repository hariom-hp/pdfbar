import Foundation

enum ToolRegistry {

    static let all: [Tool] = organize + convert + edit + security + advanced + server

    static func tools(in category: ToolCategory) -> [Tool] {
        all.filter { $0.category == category }
    }

    static func tool(_ id: String) -> Tool? {
        all.first { $0.id == id }
    }

    // MARK: - Organize

    private static let organize: [Tool] = [
        Tool(id: "merge", name: "Merge", category: .organize, symbol: "arrow.triangle.merge",
             summary: "Combine several PDFs into one, in the order you list them.",
             multiInput: true),

        Tool(id: "split", name: "Split", category: .organize, symbol: "scissors",
             summary: "Break one PDF into several files.",
             params: [
                ToolParam(key: "mode", label: "Split by",
                          kind: .choice(["Page ranges", "Every N pages", "Each page separately"], default: 0)),
                ToolParam(key: "ranges", label: "Ranges", kind: .pages(default: "1-3, 4-6"),
                          help: "Only used for \"Page ranges\".",
                          visibleWhen: { $0.int("mode") == 0 }),
                ToolParam(key: "every", label: "Pages per file", kind: .int(default: 2, min: 1, max: 500),
                          visibleWhen: { $0.int("mode") == 1 })
             ]),

        Tool(id: "extract", name: "Extract pages", category: .organize, symbol: "square.and.arrow.up.on.square",
             summary: "Pull selected pages into a new PDF.",
             params: [ToolParam(key: "pages", label: "Pages", kind: .pages(default: "1-3"))]),

        Tool(id: "remove", name: "Remove pages", category: .organize, symbol: "trash",
             summary: "Delete selected pages and keep the rest.",
             params: [ToolParam(key: "pages", label: "Pages to remove", kind: .pages(default: "1"))]),

        Tool(id: "reorder", name: "Reorder pages", category: .organize, symbol: "arrow.up.arrow.down",
             summary: "Rebuild the document in an explicit page order.",
             params: [ToolParam(key: "order", label: "New order", kind: .text(default: "3,1,2", placeholder: "3,1,2,4-6"),
                                help: "Comma-separated page numbers or ranges.")]),

        Tool(id: "rotate", name: "Rotate", category: .organize, symbol: "rotate.right",
             summary: "Rotate pages clockwise.",
             params: [
                ToolParam(key: "angle", label: "Angle", kind: .choice(["90°", "180°", "270°"], default: 0)),
                ToolParam(key: "pages", label: "Pages", kind: .pages(default: "all"))
             ]),

        Tool(id: "nup", name: "N-up", category: .organize, symbol: "rectangle.grid.2x2",
             summary: "Place several pages on each sheet — saves paper when printing.",
             params: [ToolParam(key: "perSheet", label: "Pages per sheet",
                                kind: .choice(["2", "4", "6", "9"], default: 1))]),

        Tool(id: "overlay", name: "Overlay", category: .organize, symbol: "square.on.square",
             summary: "Stamp every page of this PDF with another PDF's pages.",
             params: [
                ToolParam(key: "pages", label: "Target pages", kind: .pages(default: "all")),
                ToolParam(key: "file", label: "Overlay PDF", kind: .file(extensions: ["pdf"], prompt: "Choose overlay"))
             ]),

        Tool(id: "scale", name: "Scale to paper", category: .organize, symbol: "arrow.up.left.and.arrow.down.right",
             summary: "Resize all pages to a standard paper size.",
             params: [ToolParam(key: "size", label: "Paper size",
                                kind: .choice(["A4", "US Letter", "A3", "A5", "Legal"], default: 0))]),

        Tool(id: "autosplit", name: "Split by size", category: .organize, symbol: "chart.bar.doc.horizontal",
             summary: "Chop a long PDF into files of at most N pages.",
             params: [ToolParam(key: "maxPages", label: "Max pages per file", kind: .int(default: 10, min: 1, max: 2000))])
    ]

    // MARK: - Convert

    private static let convert: [Tool] = [
        Tool(id: "pdf2img", name: "PDF → Images", category: .convert, symbol: "photo.on.rectangle",
             summary: "Render every page to PNG, JPEG or TIFF.",
             params: [
                ToolParam(key: "format", label: "Format", kind: .choice(["PNG", "JPEG", "TIFF"], default: 0)),
                ToolParam(key: "dpi", label: "Resolution (DPI)", kind: .int(default: 150, min: 36, max: 600))
             ]),

        Tool(id: "img2pdf", name: "Images → PDF", category: .convert, symbol: "doc.badge.plus",
             summary: "Turn a set of images into a single PDF.",
             multiInput: true,
             params: [ToolParam(key: "size", label: "Fit to", kind: .choice(["Image size", "A4", "US Letter"], default: 0))]),

        Tool(id: "pdf2txt", name: "PDF → Text", category: .convert, symbol: "text.alignleft",
             summary: "Extract the text layer as plain text."),

        Tool(id: "pdf2md", name: "PDF → Markdown", category: .convert, symbol: "number",
             summary: "Convert to Markdown, inferring headings from font size."),

        Tool(id: "pdf2html", name: "PDF → HTML", category: .convert, symbol: "chevron.left.forwardslash.chevron.right",
             summary: "Convert to a standalone HTML document."),

        Tool(id: "html2pdf", name: "HTML → PDF", category: .convert, symbol: "globe",
             summary: "Render a local .html file to PDF.",
             params: [ToolParam(key: "size", label: "Paper size", kind: .choice(["A4", "US Letter"], default: 0))]),

        Tool(id: "url2pdf", name: "URL → PDF", category: .convert, symbol: "link",
             summary: "Render a web page to PDF.",
             params: [
                ToolParam(key: "url", label: "URL", kind: .text(default: "", placeholder: "https://example.com")),
                ToolParam(key: "size", label: "Paper size", kind: .choice(["A4", "US Letter"], default: 0))
             ])
    ]

    // MARK: - Edit

    private static let edit: [Tool] = [
        Tool(id: "watermark", name: "Watermark", category: .edit, symbol: "drop",
             summary: "Overlay text across the pages.",
             params: [
                ToolParam(key: "text", label: "Text", kind: .text(default: "CONFIDENTIAL", placeholder: "Text")),
                ToolParam(key: "size", label: "Font size", kind: .int(default: 60, min: 6, max: 400)),
                ToolParam(key: "opacity", label: "Opacity", kind: .double(default: 0.15, min: 0.02, max: 1.0)),
                ToolParam(key: "angle", label: "Angle", kind: .choice(["Diagonal", "Horizontal", "Vertical"], default: 0))
             ]),

        Tool(id: "pagenum", name: "Page numbers", category: .edit, symbol: "textformat.123",
             summary: "Number the pages.",
             params: [
                ToolParam(key: "position", label: "Position",
                          kind: .choice(["Bottom centre", "Bottom right", "Top right", "Bottom left"], default: 0)),
                ToolParam(key: "start", label: "Start at", kind: .int(default: 1, min: 0, max: 100000)),
                ToolParam(key: "format", label: "Format", kind: .text(default: "{n} / {total}", placeholder: "{n} / {total}"))
             ]),

        Tool(id: "crop", name: "Crop margins", category: .edit, symbol: "crop",
             summary: "Trim uniform margins from every page (keeps the text layer).",
             params: [
                ToolParam(key: "top", label: "Top", kind: .int(default: 36, min: 0, max: 2000)),
                ToolParam(key: "bottom", label: "Bottom", kind: .int(default: 36, min: 0, max: 2000)),
                ToolParam(key: "left", label: "Left", kind: .int(default: 36, min: 0, max: 2000)),
                ToolParam(key: "right", label: "Right", kind: .int(default: 36, min: 0, max: 2000))
             ],
             note: "Values are in points (72 pt = 1 inch)."),

        Tool(id: "stamp", name: "Stamp image", category: .edit, symbol: "seal",
             summary: "Place an image (signature, logo, seal) on the pages.",
             params: [
                ToolParam(key: "file", label: "Image", kind: .file(extensions: ["png", "jpg", "jpeg", "tiff", "pdf"], prompt: "Choose image")),
                ToolParam(key: "position", label: "Position",
                          kind: .choice(["Bottom right", "Bottom left", "Top right", "Top left", "Centre"], default: 0)),
                ToolParam(key: "width", label: "Width (% of page)", kind: .int(default: 25, min: 2, max: 100)),
                ToolParam(key: "opacity", label: "Opacity", kind: .double(default: 1.0, min: 0.05, max: 1.0)),
                ToolParam(key: "pages", label: "Pages", kind: .pages(default: "all"))
             ]),

        Tool(id: "flatten", name: "Flatten", category: .edit, symbol: "square.stack.3d.down.right",
             summary: "Burn annotations, form fields and comments into the page."),

        Tool(id: "redact", name: "Redact region", category: .edit, symbol: "eye.slash",
             summary: "Permanently remove content in a band around the page edge — headers, footers, watermarks.",
             params: [
                ToolParam(key: "top", label: "Cover top (pt)", kind: .int(default: 0, min: 0, max: 2000)),
                ToolParam(key: "bottom", label: "Cover bottom (pt)", kind: .int(default: 0, min: 0, max: 2000)),
                ToolParam(key: "left", label: "Cover left (pt)", kind: .int(default: 0, min: 0, max: 2000)),
                ToolParam(key: "right", label: "Cover right (pt)", kind: .int(default: 0, min: 0, max: 2000)),
                ToolParam(key: "style", label: "Fill", kind: .choice(["Black", "White"], default: 0))
             ],
             note: "Redaction rasterises the covered band, so the text underneath is destroyed — not just hidden."),

        Tool(id: "metadata", name: "Metadata", category: .edit, symbol: "info.circle",
             summary: "Read or rewrite title, author, subject and keywords.",
             params: [
                ToolParam(key: "title", label: "Title", kind: .text(default: "", placeholder: "leave blank to keep")),
                ToolParam(key: "author", label: "Author", kind: .text(default: "", placeholder: "leave blank to keep")),
                ToolParam(key: "subject", label: "Subject", kind: .text(default: "", placeholder: "leave blank to keep")),
                ToolParam(key: "keywords", label: "Keywords", kind: .text(default: "", placeholder: "comma, separated"))
             ])
    ]

    // MARK: - Security

    private static let security: [Tool] = [
        Tool(id: "encrypt", name: "Add password", category: .security, symbol: "lock",
             summary: "Encrypt with AES-128 using a user and owner password.",
             params: [
                ToolParam(key: "user", label: "Open password", kind: .text(default: "", placeholder: "required to open")),
                ToolParam(key: "owner", label: "Owner password", kind: .text(default: "", placeholder: "optional, for permissions"))
             ]),

        Tool(id: "decrypt", name: "Remove password", category: .security, symbol: "lock.open",
             summary: "Strip encryption from a PDF you have the password for.",
             params: [ToolParam(key: "password", label: "Password", kind: .text(default: "", placeholder: "password"))]),

        Tool(id: "sanitize", name: "Sanitize", category: .security, symbol: "sparkles",
             summary: "Remove metadata, annotations, scripts and embedded attachments."),

        Tool(id: "repair", name: "Repair", category: .security, symbol: "wrench.and.screwdriver",
             summary: "Rebuild a damaged PDF through a clean parse and re-save.")
    ]

    // MARK: - Advanced

    private static let advanced: [Tool] = [
        Tool(id: "compress", name: "Compress", category: .advanced, symbol: "arrow.down.right.and.arrow.up.left",
             summary: "Shrink the file by re-encoding page content.",
             params: [
                ToolParam(key: "quality", label: "Quality", kind: .choice(["Lossless (keep text)", "Balanced", "Small", "Tiny"], default: 1)),
                ToolParam(key: "dpi", label: "Resolution (DPI)", kind: .int(default: 150, min: 50, max: 300),
                          visibleWhen: { $0.int("quality") > 0 })
             ]),

        Tool(id: "ocr", name: "OCR", category: .advanced, symbol: "text.viewfinder",
             summary: "Recognise text with the system Vision engine and add a searchable layer.",
             params: [
                ToolParam(key: "lang", label: "Language",
                          kind: .choice(["Automatic", "English", "Hindi", "Chinese", "Spanish", "French", "German", "Arabic"], default: 0)),
                ToolParam(key: "searchable", label: "Also write a searchable PDF", kind: .toggle(default: true)),
                ToolParam(key: "dpi", label: "Render DPI", kind: .int(default: 200, min: 100, max: 400))
             ]),

        Tool(id: "info", name: "Inspect", category: .advanced, symbol: "magnifyingglass",
             summary: "Report pages, size, encryption, metadata and per-page geometry.",
             params: []),

        Tool(id: "compare", name: "Text diff", category: .advanced, symbol: "doc.on.doc",
             summary: "Compare the text of two PDFs and report what changed.",
             multiInput: true)
    ]

    // MARK: - Server

    private static let server: [Tool] = [
        Tool(id: "stirling:editor", name: "Visual editor", category: .server, symbol: "pencil.tip.crop.circle",
             summary: "Drag-and-drop editing — add text boxes, images and signatures, then export. This is the full WYSIWYG editor, and it runs in the Stirling web UI.",
             remoteOnly: true,
             note: "Native PDFBar edits pages, metadata and annotations. Editing the content itself (typing over the document) needs the Stirling server."),

        Tool(id: "stirling:open", name: "Open Stirling-PDF", category: .server, symbol: "safari",
             summary: "Open the full Stirling-PDF web UI running on your machine — every upstream feature, including the ones macOS cannot do natively.",
             remoteOnly: true),

        Tool(id: "stirling:office2pdf", name: "Office → PDF", category: .server, symbol: "doc.richtext",
             summary: "Word, Excel and PowerPoint to PDF. Needs LibreOffice, so it runs on the Stirling server.",
             remoteOnly: true),

        Tool(id: "stirling:pdf2word", name: "PDF → Word", category: .server, symbol: "doc.text",
             summary: "Convert to .docx on the Stirling server.",
             remoteOnly: true),

        Tool(id: "stirling:pdf2ppt", name: "PDF → PowerPoint", category: .server, symbol: "rectangle.on.rectangle",
             summary: "Convert to .pptx on the Stirling server.",
             remoteOnly: true),

        Tool(id: "stirling:pdf2pdfa", name: "PDF → PDF/A", category: .server, symbol: "checkmark.seal",
             summary: "Archive-compliant conversion via Ghostscript on the Stirling server.",
             remoteOnly: true),

        Tool(id: "stirling:extractimg", name: "Extract images", category: .server, symbol: "photo.stack",
             summary: "Pull original embedded images at native resolution.",
             remoteOnly: true)
    ]
}
