import Cocoa
import WebKit
import UniformTypeIdentifiers

let markdownExtensions = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt"]
let titlebarCenterY: CGFloat = 20
let trafficLightX: CGFloat = 14

func isMarkdown(_ path: String) -> Bool {
    markdownExtensions.contains((path as NSString).pathExtension.lowercased())
}

func mtime(_ path: String) -> Double {
    let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    return (date?.timeIntervalSince1970 ?? 0) * 1000
}

let cardColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0x1e / 255, green: 0x1e / 255, blue: 0x20 / 255, alpha: 1)
        : .white
}

// MARK: - Web view with native window dragging + file drops

final class DocWebView: WKWebView {
    var dragRects: [NSRect] = []
    var noDragRects: [NSRect] = []
    var onDrop: (([String]) -> Void)?
    var onDragState: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let wp = NSPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
        if dragRects.contains(where: { $0.contains(wp) }) && !noDragRects.contains(where: { $0.contains(wp) }) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
            return
        }
        super.mouseDown(with: event)
    }

    private func paths(_ info: NSDraggingInfo) -> [String] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map(\.path).filter(isMarkdown)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !paths(sender).isEmpty { onDragState?(true); return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        paths(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragState?(false)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let ps = paths(sender)
        guard !ps.isEmpty else { return super.performDragOperation(sender) }
        onDragState?(false)
        onDrop?(ps)
        return true
    }
}

// MARK: - One window per document

final class DocWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    let path: String
    let initialMode: String
    let window: NSWindow
    let webView: DocWebView
    var closing = false
    weak var app: AppDelegate?

    init(path: String, mode: String, app: AppDelegate) {
        self.path = path
        self.initialMode = mode
        self.app = app

        let size = NSSizeFromString(UserDefaults.standard.string(forKey: "windowSize") ?? "")
        let frame = NSRect(x: 0, y: 0, width: size.width >= 400 ? size.width : 860, height: size.height >= 300 ? size.height : 900)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = cardColor
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .automatic
        window.title = (path as NSString).lastPathComponent
        window.representedURL = URL(fileURLWithPath: path)

        let config = WKWebViewConfiguration()
        webView = DocWebView(frame: window.contentView!.bounds, configuration: config)
        super.init()

        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "bridge")
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        webView.onDrop = { [weak app] ps in ps.forEach { app?.open($0) } }
        webView.onDragState = { [weak self] on in self?.callJS("app.dragState", on) }
        window.contentView = webView
        window.delegate = self

        let webDir = Bundle.main.resourceURL!.appendingPathComponent("web")
        webView.loadFileURL(webDir.appendingPathComponent("index.html"), allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func show(cascadeFrom other: NSWindow?) {
        if let other {
            window.setFrameTopLeftPoint(NSPoint(x: other.frame.minX + 26, y: other.frame.maxY - 26))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        positionTrafficLights()
    }

    func positionTrafficLights() {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let container = close.superview?.superview else { return }
        let height = titlebarCenterY + close.frame.minY + close.frame.height / 2
        var f = container.frame
        f.size.height = height
        f.origin.y = window.frame.height - height
        container.frame = f
        let spacing = mini.frame.minX - close.frame.minX
        for (i, b) in [close, mini, zoom].enumerated() {
            b.setFrameOrigin(NSPoint(x: trafficLightX + CGFloat(i) * spacing, y: b.frame.minY))
        }
    }

    func callJS(_ fn: String, _ arg: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: [arg], options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("\(fn)(...\(json))", completionHandler: nil)
    }

    func flush(_ done: @escaping () -> Void) {
        webView.evaluateJavaScript("window.app ? app.flush() : true") { _, _ in done() }
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        positionTrafficLights()
        if !window.styleMask.contains(.fullScreen) {
            UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: "windowSize")
        }
    }
    func windowDidBecomeKey(_ notification: Notification) { positionTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { positionTrafficLights(); callJS("app.setFullscreen", false) }
    func windowWillEnterFullScreen(_ notification: Notification) { callJS("app.setFullscreen", true) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closing { return true }
        flush { [weak self] in
            self?.closing = true
            self?.window.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        app?.docClosed(self)
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if action.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(url.isFileURL ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    // MARK: Bridge

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else {
            return replyHandler(nil, "bad message")
        }
        let args = body["args"] as? [String: Any] ?? [:]
        let p = args["path"] as? String ?? path

        switch cmd {
        case "init":
            replyHandler([
                "path": path,
                "mode": initialMode,
                "home": NSHomeDirectory(),
                "prefs": UserDefaults.standard.string(forKey: "prefs") ?? "",
            ], nil)

        case "setPrefs":
            UserDefaults.standard.set(args["json"] as? String, forKey: "prefs")
            app?.broadcastPrefs(args["json"] as? String ?? "", except: self)
            replyHandler(true, nil)

        case "stat":
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: p, isDirectory: &isDir)
            replyHandler(["exists": exists, "isDir": isDir.boolValue, "mtime": exists ? mtime(p) : 0], nil)

        case "readFile":
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: p))
                replyHandler(["content": String(decoding: data, as: UTF8.self), "mtime": mtime(p)], nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }

        case "writeFile":
            do {
                try (args["content"] as? String ?? "").write(toFile: p, atomically: true, encoding: .utf8)
                replyHandler(["mtime": mtime(p)], nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }

        case "openPath":
            if FileManager.default.fileExists(atPath: p) {
                if isMarkdown(p) { app?.open(p) } else { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
            }
            replyHandler(true, nil)

        case "openExternal":
            if let s = args["url"] as? String, let url = URL(string: s) { NSWorkspace.shared.open(url) }
            replyHandler(true, nil)

        case "setEdited":
            window.isDocumentEdited = args["edited"] as? Bool ?? false
            replyHandler(true, nil)

        case "dragRects":
            func rects(_ v: Any?) -> [NSRect] {
                (v as? [[Double]] ?? []).compactMap { $0.count == 4 ? NSRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
            }
            webView.dragRects = rects(args["drag"])
            webView.noDragRects = rects(args["noDrag"])
            replyHandler(true, nil)

        default:
            replyHandler(nil, "unknown command \(cmd)")
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var docs: [DocWindow] = []
    var didOpenAtLaunch = false

    var keyDoc: DocWindow? { docs.first { $0.window.isKeyWindow } ?? docs.first { $0.window.isMainWindow } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if self.docs.isEmpty && !self.didOpenAtLaunch { self.showOpenPanel() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didOpenAtLaunch = true
        urls.filter(\.isFileURL).forEach { open($0.path) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && docs.isEmpty { showOpenPanel() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !docs.isEmpty else { return .terminateNow }
        let group = DispatchGroup()
        for d in docs { group.enter(); d.flush { group.leave() } }
        var replied = false
        let reply = { if !replied { replied = true; NSApp.reply(toApplicationShouldTerminate: true) } }
        group.notify(queue: .main, execute: reply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reply)
        return .terminateLater
    }

    func open(_ rawPath: String, mode: String = "read") {
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return }
        if let existing = docs.first(where: { $0.path == path }) {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let doc = DocWindow(path: path, mode: mode, app: self)
        let anchor = keyDoc?.window
        docs.append(doc)
        doc.show(cascadeFrom: anchor)
        NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: path))
    }

    func docClosed(_ doc: DocWindow) {
        docs.removeAll { $0 === doc }
    }

    func broadcastPrefs(_ json: String, except: DocWindow) {
        for d in docs where d !== except { d.callJS("app.setPrefs", json) }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = markdownExtensions.compactMap { UTType(filenameExtension: $0) }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            panel.urls.forEach { open($0.path) }
        }
    }

    @objc func openDocument(_ sender: Any?) { showOpenPanel() }

    @objc func newDocument(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        if let current = keyDoc?.path {
            panel.directoryURL = URL(fileURLWithPath: (current as NSString).deletingLastPathComponent)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let title = url.deletingPathExtension().lastPathComponent
        try? "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
        open(url.path, mode: "edit")
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard let p = keyDoc?.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    }

    @objc func runCommand(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        keyDoc?.callJS("app.command", name)
    }

    // MARK: Menu

    func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Folio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Folio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        item(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Folio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        submenu(main, "Folio", appMenu)

        let file = NSMenu(title: "File")
        item(file, "New", #selector(newDocument(_:)), "n", target: self)
        item(file, "Open…", #selector(openDocument(_:)), "o", target: self)
        file.addItem(.separator())
        cmd(file, "Save", "save", "s")
        item(file, "Reveal in Finder", #selector(revealInFinder(_:)), "r", [.command, .shift], target: self)
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        submenu(main, "File", file)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        cmd(edit, "Find…", "find", "f")
        submenu(main, "Edit", edit)

        let view = NSMenu(title: "View")
        cmd(view, "Toggle Editing", "toggleEdit", "e")
        cmd(view, "Read", "modeRead", "1")
        cmd(view, "Edit", "modeEdit", "2")
        cmd(view, "Side by Side", "modeSplit", "3")
        view.addItem(.separator())
        cmd(view, "Bigger Text", "zoomIn", "+")
        cmd(view, "Smaller Text", "zoomOut", "-")
        cmd(view, "Actual Size", "zoomReset", "0")
        view.addItem(.separator())
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        submenu(main, "View", view)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        submenu(main, "Window", windowMenu)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    func submenu(_ main: NSMenu, _ title: String, _ menu: NSMenu) {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        main.addItem(it)
    }

    @discardableResult
    func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
              _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let it = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = target
        return it
    }

    func cmd(_ menu: NSMenu, _ title: String, _ name: String, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) {
        let it = item(menu, title, #selector(runCommand(_:)), key, mods, target: self)
        it.representedObject = name
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(runCommand(_:)) || menuItem.action == #selector(revealInFinder(_:)) {
            return keyDoc != nil
        }
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
