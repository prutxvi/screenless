// Screenless — native Mac app: control a broken-screen Android phone.
// Professional AppKit UI: semantic colors (auto dark mode), SF Symbols,
// device cards in a scroll area, per-device Mirror buttons, status pill.
// Engine = the repo's phone.sh launchers (same watchdog + device records).

import AppKit

private extension String {
    var trim: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// semantic accents that read in light & dark
private let successColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.30, green: 0.78, blue: 0.47, alpha: 1)   // #4CC778
        : NSColor(red: 0.02, green: 0.59, blue: 0.41, alpha: 1)   // #059669
}
private let warnColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.98, green: 0.75, blue: 0.27, alpha: 1)
        : NSColor(red: 0.85, green: 0.55, blue: 0.10, alpha: 1)
}
private let dangerColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 1.00, green: 0.45, blue: 0.45, alpha: 1)
        : NSColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let repoDir = ("~/Documents/Projects/screenless/macos" as NSString).expandingTildeInPath
    let recordDir = ("~/.config/screenless/devices" as NSString).expandingTildeInPath
    let childEnv: [String: String] = [
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": NSHomeDirectory(),
    ]

    var window: NSWindow!
    var deviceStack: NSStackView!
    var scrollArea: NSScrollView!
    var statusLabel: NSTextField!
    var statusPill: NSTextField!
    var stopButton: NSButton!
    var refreshTimer: Timer?
    var child: Process?
    var lastStatus = "Ready."
    var lastSignature = ""

    // MARK: - window & layout

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "screenless"
        window.subtitle = "control a broken-screen Android phone"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("screenless-main")
        window.minSize = NSSize(width: 460, height: 360)

        buildUI()
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    private func buildUI() {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content
        let cv = content
        let pad: CGFloat = 20

        // header: app identity + live status pill on the right
        let title = label("screenless", size: 17, weight: .semibold, color: .labelColor)
        let subtitle = label("Control a broken-screen Android phone over USB or Wi-Fi", size: 11,
                             color: .secondaryLabelColor)
        let titleCol = NSStackView(views: [title, subtitle])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 1
        statusPill = pill()

        let header = NSStackView(views: [titleCol, spacer(), statusPill])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        // scrollable device card area
        deviceStack = NSStackView()
        deviceStack.orientation = .vertical
        deviceStack.alignment = .leading
        deviceStack.spacing = 10
        deviceStack.translatesAutoresizingMaskIntoConstraints = false

        scrollArea = NSScrollView()
        scrollArea.documentView = deviceStack
        scrollArea.hasVerticalScroller = true
        scrollArea.drawsBackground = false
        scrollArea.verticalScroller?.controlSize = .small
        scrollArea.translatesAutoresizingMaskIntoConstraints = false

        // footer actions
        let mirrorBtn = symbolButton("Mirror", symbol: "play.fill", action: #selector(mirrorAny(_:)))
        stopButton = symbolButton("Stop", symbol: "stop.fill", action: #selector(stop(_:)))
        let pairBtn = symbolButton("Pair wizard…", symbol: "antenna.radiowaves.left.and.right",
                                   action: #selector(pairWizard(_:)))
        let recordsBtn = symbolButton("Saved devices", symbol: "folder", action: #selector(openRecords(_:)))
        let shotBtn = symbolButton("Snapshot", symbol: "camera", action: #selector(saveSnapshot(_:)))
        let footer = NSStackView(views: [mirrorBtn, stopButton, spacer(), shotBtn, pairBtn, recordsBtn])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = label("Ready.", size: 11, color: .secondaryLabelColor)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(header)
        cv.addSubview(scrollArea)
        cv.addSubview(footer)
        cv.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: cv.topAnchor, constant: pad),
            header.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            header.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

            scrollArea.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scrollArea.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            scrollArea.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            scrollArea.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),

            footer.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            footer.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            footer.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad + 2),
            statusLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            statusLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
        ])
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }

    private func pill() -> NSTextField {
        let l = NSTextField(labelWithString: "● Checking…")
        l.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        return l
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }

    private func symbolButton(_ title: String, symbol: String, action: Selector) -> NSButton {        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        b.imagePosition = .imageLeading
        b.setAccessibilityLabel(title)
        return b
    }

    // MARK: - refresh

    private func refresh() {
        let busy = child?.isRunning ?? false
        let tools = toolchainPresent()
        let devices = tools ? adbDevices() : []
        let signature = devices.map { "\($0.serial)|\($0.state)|\($0.usb)" }.joined(separator: ";")
            + "|\(busy)|\(tools)"

        DispatchQueue.main.async { [self] in
            stopButton?.isEnabled = busy
            statusLabel?.stringValue = lastStatus
            updatePill(busy: busy, tools: tools, devices: devices)
            if signature != lastSignature {
                lastSignature = signature
                rebuildCards(devices: devices, tools: tools)
            }
        }
    }

    private func updatePill(busy: Bool, tools: Bool, devices: [Device]) {
        guard let pill = statusPill else { return }
        let color: NSColor
        let text: String
        if !tools {
            (color, text) = (dangerColor, "adb or scrcpy missing")
        } else if busy {
            (color, text) = (warnColor, "Mirroring…")
        } else if let first = devices.first(where: { $0.state == "device" }) {
            (color, text) = (successColor, first.usb ? "Ready · USB" : "Ready · Wi-Fi")
        } else if devices.contains(where: { $0.state == "unauthorized" }) {
            (color, text) = (warnColor, "Tap Allow on the phone")
        } else if !devices.isEmpty {
            (color, text) = (warnColor, "Check the cable")
        } else {
            (color, text) = (NSColor.secondaryLabelColor, "No phone connected")
        }
        let dot = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: color])
        dot.append(NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ]))
        pill.attributedStringValue = dot
    }

    private func rebuildCards(devices: [Device], tools: Bool) {
        deviceStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard tools else {
            let c = infoCard(headline: "adb or scrcpy not found",
                detail: "Install with Terminal:  brew install scrcpy\nThen reopen screenless.",
                symbol: "wrench.and.screwdriver", tint: dangerColor)
            deviceStack.addArrangedSubview(c)
            cardNeedsWidth(c)
            return
        }
        if devices.isEmpty {
            let c = infoCard(headline: "No phone connected",
                detail: "Plug the phone in over USB — screenless saves its Wi-Fi address and\nre-arms wireless mode so the next launch needs no cable.",
                symbol: "iphone.slash", tint: NSColor.tertiaryLabelColor)
            deviceStack.addArrangedSubview(c)
            cardNeedsWidth(c)
        } else {
            for d in devices {
                let card = deviceCard(d)
                deviceStack.addArrangedSubview(card)
                cardNeedsWidth(card)
            }
        }
    }

    // (opencode) width pin must happen AFTER the card joins the stack's hierarchy,
    // or the constraint throws ("no common ancestor")
    private func cardNeedsWidth(_ card: NSView) {
        card.widthAnchor.constraint(equalTo: deviceStack.widthAnchor).isActive = true
    }

    // MARK: - cards

    private func deviceCard(_ d: Device) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let icon: (String, NSColor)
        let note: String
        switch d.state {
        case "device":
            icon = ("checkmark.circle.fill", successColor)
            note = d.usb ? "USB — ready to mirror" : "Wi-Fi — ready to mirror"
        case "unauthorized":
            icon = ("lock.shield.fill", warnColor)
            note = "Tap Allow on the phone — or pair with a key"
        default:
            icon = ("exclamationmark.triangle.fill", warnColor)
            note = "\(d.state) — replug or wait"
        }

        let symView = NSImageView(image: NSImage(systemSymbolName: icon.0,
                                                 accessibilityDescription: note)!)
        symView.contentTintColor = icon.1
        symView.translatesAutoresizingMaskIntoConstraints = false

        let name = label(model(for: d.serial), size: 13, weight: .semibold, color: .labelColor)
        let sub = label("\(note)  ·  \(d.serial)", size: 10, color: .secondaryLabelColor)
        let textCol = NSStackView(views: [name, sub])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        textCol.translatesAutoresizingMaskIntoConstraints = false

        let mirrorBtn = symbolButton("Mirror", symbol: "play.fill", action: #selector(mirrorDevice(_:)))
        mirrorBtn.identifier = NSUserInterfaceItemIdentifier(d.serial)
        mirrorBtn.isEnabled = d.state == "device"
        mirrorBtn.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(symView)
        card.addSubview(textCol)
        card.addSubview(mirrorBtn)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 66),
            symView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            symView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textCol.leadingAnchor.constraint(equalTo: symView.trailingAnchor, constant: 12),
            textCol.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textCol.trailingAnchor.constraint(lessThanOrEqualTo: mirrorBtn.leadingAnchor, constant: -12),
            mirrorBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            mirrorBtn.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    private func infoCard(headline: String, detail: String, symbol: String, tint: NSColor) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let symView = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: headline)!)
        symView.contentTintColor = tint
        symView.translatesAutoresizingMaskIntoConstraints = false

        let col = NSStackView(views: [
            label(headline, size: 13, weight: .semibold, color: .labelColor),
            label(detail, size: 10, color: .secondaryLabelColor),
        ])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 3
        col.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(symView)
        card.addSubview(col)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 84),
            symView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            symView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            col.leadingAnchor.constraint(equalTo: symView.trailingAnchor, constant: 12),
            col.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            col.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
        ])
        return card
    }

    // MARK: - actions

    @objc func mirrorDevice(_ sender: NSButton) {
        spawnPhone(sender.identifier?.rawValue)
    }

    @objc func mirrorAny(_ sender: Any?) { spawnPhone(nil) }

    @objc func stop(_ sender: Any?) {
        guard let p = child, p.isRunning else {
            lastStatus = "Nothing running."
            return
        }
        _ = sh(["/usr/bin/pkill", "-f", "scrcpy -s"])   // ends the mirror window + the watchdog too
        p.interrupt()
        lastStatus = "Stopping…"
        refresh()
    }

    private func spawnPhone(_ serial: String?) {
        if child?.isRunning ?? false { stop(nil) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = serial.map { [repoDir + "/phone.sh", "-s", $0] } ?? [repoDir + "/phone.sh"]
        p.environment = childEnv
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            let code = proc.terminationStatus
            let tail = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = tail.split(separator: "\n").suffix(3).joined(separator: " · ")
            DispatchQueue.main.async {
                self.child = nil
                self.lastStatus = code == 0
                    ? "Mirroring ended normally."
                    : "Mirroring ended (exit \(code)): \(String(lines.prefix(140)))"
                self.refresh()
            }
        }
        do {
            try p.run()
            child = p
            lastStatus = serial != nil ? "Launching \(serial!)…" : "Launching with phone.sh (watchdog armed)…"
            refresh()
        } catch {
            lastStatus = "Could not start phone.sh: \(error.localizedDescription)"
        }
    }

    @objc func pairWizard(_ sender: Any?) {
        sh(["/usr/bin/open", "-a", "Terminal", repoDir + "/pair.sh"])
        lastStatus = "Pair wizard opened in Terminal — finish it there."
        refresh()
    }

    @objc func openRecords(_ sender: Any?) {
        sh(["/usr/bin/open", recordDir])
        lastStatus = "Opened the saved-device records folder."
        refresh()
    }

    // Saves the app window as a PNG into the repository's media folders (docs/ + site/) —
    // names depend on the live state: "idle" or "mirroring". No Screen Recording
    // permission is needed because the window renders its own content to a PDF buffer.
    @objc func saveSnapshot(_ sender: Any?) {
        guard let content = window.contentView else { return }
        let pdfData = content.dataWithPDF(inside: content.bounds)
        guard let image = NSImage(data: pdfData),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            lastStatus = "Snapshot failed."
            refresh()
            return
        }
        let busy = child?.isRunning ?? false
        let name = busy ? "app-mac-mirroring.png" : "app-mac-idle.png"
        let docs = (repoDir + "/../docs/media/" + name)
        let site = (repoDir + "/../../site/media/" + name)
        do {
            for path in [docs, site] {
                let dir = (path as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try png.write(to: URL(fileURLWithPath: path))
            }
            lastStatus = "Snapshot saved: \(name) (docs/media + site/media)"
            _ = sh(["/usr/bin/open", "-R", docs])
        } catch {
            lastStatus = "Snapshot failed: \(error.localizedDescription)"
        }
        refresh()
    }

    // MARK: - adb plumbing

    struct Device { let serial: String; let state: String; let usb: Bool }

    private func adbDevices() -> [Device] {
        let out = sh(["adb", "devices", "-l"])
        var result: [Device] = []
        for line in out.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() {
            let cols = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 3, !line.contains("List of devices") else { continue }
            result.append(Device(serial: cols[0], state: cols[1], usb: line.contains("usb:")))
        }
        return result
    }

    private func model(for serial: String) -> String {
        let m = sh(["adb", "-s", serial, "shell", "getprop", "ro.product.model"]).trim
        if !m.isEmpty { return m }
        let safe = String(serial.map {
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains($0) ? $0 : "_"
        })
        let path = recordDir + "/\(safe).conf"
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            for l in contents.split(separator: "\n") {
                if l.hasPrefix("model=") { return String(l.dropFirst(6)) }
            }
        }
        return serial
    }

    private func toolchainPresent() -> Bool {
        !sh(["/usr/bin/which", "adb"]).trim.isEmpty && !sh(["/usr/bin/which", "scrcpy"]).trim.isEmpty
    }

    private func resolve(_ name: String) -> String {
        if name.contains("/") { return name }
        for dir in (childEnv["PATH"] ?? "").split(separator: ":") {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return name   // fall back: Process will report the failure in lastStatus
    }

    private func sh(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: resolve(args[0]))
        p.arguments = Array(args.dropFirst())
        p.environment = childEnv
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
