import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if arguments.contains("--dump-menu") {
    exit(Headless.dumpMenu() ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-ui") {
    let toolID = arguments.count > index + 1 ? arguments[index + 1] : "merge"
    let path = arguments.count > index + 2 ? arguments[index + 2] : "/tmp/pdfbar-ui.png"
    let light = arguments.contains("--light")
    let ok = Headless.render(toolID: toolID, to: path, dark: !light)
    print(ok ? "rendered \(toolID) → \(path)" : "render failed")
    exit(ok ? 0 : 1)
}

// Only one PDFBar may own the menu bar. A second copy asks the running
// instance to surface its window, then exits.
let supportDir = ("~/Library/Application Support/PDFBar" as NSString).expandingTildeInPath
try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
let lockPath = supportDir + "/instance.lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD >= 0 && flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("dev.pdfbar.app.show"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
