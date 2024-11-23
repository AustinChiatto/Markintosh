import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var recentCharacters = [String]()
    var potentialMatches: [String] = []
    var globalMonitor: Any?
    
    // Define the shortcuts to trigger in Notes based on detected patterns
    let mdCommands: [String: [CGKeyCode]] = [
        "#": [CGKeyCode(55), CGKeyCode(56), CGKeyCode(17)],                // ⇧ ⌘ T
        "##": [CGKeyCode(55), CGKeyCode(56), CGKeyCode(4)],                // ⇧ ⌘ H
        "###": [CGKeyCode(55), CGKeyCode(56), CGKeyCode(38)],              // ⇧ ⌘ J
        "####": [CGKeyCode(55), CGKeyCode(56), CGKeyCode(11)],             // ⇧ ⌘ B
        "```": [CGKeyCode(55), CGKeyCode(56), CGKeyCode(46)],              // ⇧ ⌘ M
        ">": [CGKeyCode(55), CGKeyCode(39)],                               // ⌘'
        "[]": [CGKeyCode(55), CGKeyCode(56), CGKeyCode(37)],               // ⇧ ⌘ L
    ]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupStatusItem()
        checkAndRequestAccessibilityPermissions()
        addAppActiveObserver()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        removeGlobalMonitor()
        NotificationCenter.default.removeObserver(self)
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(named: "menuBarIcon")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
    
    func checkAndRequestAccessibilityPermissions() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard !AXIsProcessTrusted() else { return }
            
            let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSObject: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
    
    func setupGlobalMonitoring() {
        guard globalMonitor == nil else {
            return
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUpEvent(event)
        }
    }

    func removeGlobalMonitor() {
        if globalMonitor != nil {
            NSEvent.removeMonitor(globalMonitor!)
            globalMonitor = nil
        }
    }

    func addAppActiveObserver() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appDidActivate), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc func appDidActivate(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.Notes" else {
            removeGlobalMonitor()
            return
        }
        setupGlobalMonitoring()
    }
    
    func handleKeyUpEvent(_ event: NSEvent) {
        guard let characters = event.characters,
              let notesApp = NSWorkspace.shared.frontmostApplication,
              notesApp.bundleIdentifier == "com.apple.Notes" else {
            return
        }

        // check for return/enter key or new line character
        if event.keyCode == 36 || characters.contains("\n") || characters.contains("\r") {
            recentCharacters.removeAll()
            potentialMatches.removeAll()
            return
        }

        guard "#`>[] ".contains(where: characters.contains) else {
            return
        }

        updatePotentialMatches(with: characters)
        
        // trigger formatting when space is entered
        if characters.contains(" ") {
            let recentString = recentCharacters.joined()
            if let command = potentialMatches.first(where: { command in
                return recentString.hasPrefix(command) && mdCommands.keys.contains(command)
            }) {
                if let shortcutKeys = mdCommands[command] {
                    simulateBackspace(count: command.count + 1)
                    triggerFormatting(keys: shortcutKeys)
                }
                recentCharacters.removeAll()
                potentialMatches.removeAll()
            }
        }
    }

    
    let maxRecentCharacters = 6
    
    func updatePotentialMatches(with characters: String) {
        let validCharacters = characters.filter { $0 != " " }
        
        recentCharacters.append(contentsOf: validCharacters.map { String($0) })
        
        // Trim the array if it exceeds the maximum length
        if recentCharacters.count > maxRecentCharacters {
            recentCharacters.removeFirst(recentCharacters.count - maxRecentCharacters)
        }
        
        if potentialMatches.isEmpty {
            potentialMatches = mdCommands.keys.filter { $0.hasPrefix(recentCharacters.joined()) }
        } else {
            potentialMatches = potentialMatches.filter { $0.hasPrefix(recentCharacters.joined()) }
        }
        
        if potentialMatches.isEmpty {
            recentCharacters.removeAll()
            potentialMatches.removeAll()
        }
    }
    
    func simulateBackspace(count: Int) {
        let backspace = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(51), keyDown: true)
        let backspaceUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(51), keyDown: false)
        
        for _ in 0..<count {
            backspace?.post(tap: .cghidEventTap)
            backspaceUp?.post(tap: .cghidEventTap)
        }
    }
    
    // Trigger specified Apple Notes formatting shortcut
    func triggerFormatting(keys: [CGKeyCode]) {
        let source = CGEventSource(stateID: .hidSystemState)

        func createKeyEvent(key: CGKeyCode, keyDown: Bool) -> CGEvent? {
            return CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
        }
        
        // Determine the modifier flags based on the keys
        let containsShift = keys.contains(CGKeyCode(56))
        let containsCommand = keys.contains(CGKeyCode(55))
        let keyFlags: CGEventFlags = {
            var flags: CGEventFlags = []
            if containsCommand { flags.insert(.maskCommand) }
            if containsShift { flags.insert(.maskShift) }
            return flags
        }()

        keys.forEach { key in
            if let event = createKeyEvent(key: key, keyDown: true) {
                event.flags = keyFlags
                event.post(tap: CGEventTapLocation.cghidEventTap)
            }
        }

        keys.reversed().forEach { key in
            if let event = createKeyEvent(key: key, keyDown: false) {
                event.flags = keyFlags
                event.post(tap: CGEventTapLocation.cghidEventTap)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
