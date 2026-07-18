import AppKit

// AppKit entry point rather than a SwiftUI `App`. Every window here is
// NSWindow-managed, and the placeholder `Settings` scene SwiftUI requires was
// stealing the ⌘, menu item and opening an empty window of its own.
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
