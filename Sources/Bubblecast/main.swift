import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
let appMenuItem = NSMenuItem()
appMenuItem.submenu = NSMenu()
appMenuItem.submenu?.addItem(withTitle: "About Bubblecast",
                             action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenuItem.submenu?.addItem(.separator())
appMenuItem.submenu?.addItem(withTitle: "Quit Bubblecast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
app.mainMenu = NSMenu()
app.mainMenu?.addItem(appMenuItem)
app.delegate = delegate
app.run()
