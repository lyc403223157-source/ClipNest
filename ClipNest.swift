import AppKit
import ApplicationServices
import Carbon
import Foundation

extension Notification.Name {
    static let clipStoreDidChange = Notification.Name("clipStoreDidChange")
}

struct ClipItem: Codable, Equatable {
    var id: String
    var title: String
    var content: String
    var kind: String? = nil
    var imageFileName: String? = nil
    var titleIsCustom: Bool? = nil

    var isImage: Bool { kind == "image" && imageFileName != nil }
    var hasCustomTitle: Bool { titleIsCustom ?? !title.isEmpty }
}

struct ClipTag: Codable, Equatable {
    var id: String
    var name: String
    var isRecent: Bool
    var items: [ClipItem]
}

final class ClipStore {
    private(set) var tags: [ClipTag] = []
    private let dataURL: URL
    private let imageDirectory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("ClipNest", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dataURL = directory.appendingPathComponent("clips.json")
        imageDirectory = directory.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: dataURL),
           let decoded = try? JSONDecoder().decode([ClipTag].self, from: data),
           !decoded.isEmpty {
            tags = decoded
        } else {
            tags = [
                ClipTag(id: "recent", name: "最近", isRecent: true, items: []),
                ClipTag(id: "docs", name: "文档", isRecent: false, items: [
                    ClipItem(id: UUID().uuidString, title: "产品使用文档", content: "https://docs.example.com/product", titleIsCustom: true),
                    ClipItem(id: UUID().uuidString, title: "API 接口文档", content: "https://docs.example.com/api", titleIsCustom: true)
                ]),
                ClipTag(id: "replies", name: "常用回复", isRecent: false, items: [
                    ClipItem(id: UUID().uuidString, title: "稍后回复", content: "收到，我先确认一下，稍后给你回复。", titleIsCustom: true)
                ])
            ]
            save()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(tags) {
            try? data.write(to: dataURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .clipStoreDidChange, object: self)
    }

    func recordClipboard(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let recentIndex = tags.firstIndex(where: { $0.isRecent }) else { return }
        tags[recentIndex].items.removeAll { !$0.isImage && $0.content == text }
        tags[recentIndex].items.insert(
            ClipItem(id: UUID().uuidString, title: "", content: text, titleIsCustom: false),
            at: 0
        )
        save()
    }

    func removeRecentText(_ text: String) {
        guard let recentIndex = tags.firstIndex(where: { $0.isRecent }) else { return }
        tags[recentIndex].items.removeAll { !$0.isImage && $0.content == text }
        save()
    }

    func recordPasteboard(_ pasteboard: NSPasteboard) {
        if let image = image(from: pasteboard) {
            recordClipboardImage(image)
        } else if let text = pasteboard.string(forType: .string) {
            recordClipboard(text)
        }
    }

    func image(from pasteboard: NSPasteboard) -> NSImage? {
        let supportedTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("org.webmproject.webp")
        ]
        guard let availableType = pasteboard.availableType(from: supportedTypes),
              let data = pasteboard.data(forType: availableType) else { return nil }
        return NSImage(data: data)
    }

    func recordClipboardImage(_ image: NSImage) {
        guard let pngData = pngData(for: image),
              let recentIndex = tags.firstIndex(where: { $0.isRecent }) else { return }

        if let existingIndex = tags[recentIndex].items.firstIndex(where: { item in
            guard item.isImage, let fileName = item.imageFileName else { return false }
            return (try? Data(contentsOf: imageDirectory.appendingPathComponent(fileName))) == pngData
        }) {
            let existing = tags[recentIndex].items.remove(at: existingIndex)
            tags[recentIndex].items.insert(existing, at: 0)
            save()
            return
        }

        let fileName = UUID().uuidString + ".png"
        do {
            try pngData.write(to: imageDirectory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            return
        }
        tags[recentIndex].items.insert(
            ClipItem(
                id: UUID().uuidString,
                title: "",
                content: "",
                kind: "image",
                imageFileName: fileName,
                titleIsCustom: false
            ),
            at: 0
        )
        save()
    }

    @discardableResult
    func addTag(named name: String) -> String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let id = UUID().uuidString
        tags.append(ClipTag(id: id, name: value, isRecent: false, items: []))
        save()
        return id
    }

    @discardableResult
    func moveRecentItem(itemID: String, toTagID tagID: String) -> Bool {
        guard let recentIndex = tags.firstIndex(where: { $0.isRecent }),
              let itemIndex = tags[recentIndex].items.firstIndex(where: { $0.id == itemID }),
              let targetIndex = tags.firstIndex(where: { $0.id == tagID && !$0.isRecent }) else { return false }
        var item = tags[recentIndex].items.remove(at: itemIndex)
        item.title = ""
        item.titleIsCustom = false
        tags[targetIndex].items.append(item)
        save()
        return true
    }

    func deleteTag(at index: Int) {
        guard tags.indices.contains(index), !tags[index].isRecent else { return }
        tags[index].items.forEach(removeImageFileIfNeeded)
        tags.remove(at: index)
        save()
    }

    func addItem(to tagIndex: Int, title: String, content: String) {
        guard tags.indices.contains(tagIndex), !tags[tagIndex].isRecent,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let customTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tags[tagIndex].items.append(
            ClipItem(
                id: UUID().uuidString,
                title: customTitle,
                content: content,
                titleIsCustom: !customTitle.isEmpty
            )
        )
        save()
    }

    func addImageItem(to tagIndex: Int, image: NSImage) {
        guard tags.indices.contains(tagIndex), !tags[tagIndex].isRecent,
              let pngData = pngData(for: image) else { return }
        let fileName = UUID().uuidString + ".png"
        do {
            try pngData.write(to: imageDirectory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            return
        }
        tags[tagIndex].items.append(
            ClipItem(
                id: UUID().uuidString,
                title: "",
                content: "",
                kind: "image",
                imageFileName: fileName,
                titleIsCustom: false
            )
        )
        save()
    }

    func updateItem(tagIndex: Int, itemIndex: Int, title: String, content: String) {
        guard tags.indices.contains(tagIndex), tags[tagIndex].items.indices.contains(itemIndex) else { return }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let customTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tags[tagIndex].items[itemIndex].title = customTitle
        tags[tagIndex].items[itemIndex].titleIsCustom = !customTitle.isEmpty
        tags[tagIndex].items[itemIndex].content = content
        save()
    }

    func updateItemTitle(tagIndex: Int, itemIndex: Int, title: String) {
        guard tags.indices.contains(tagIndex), tags[tagIndex].items.indices.contains(itemIndex) else { return }
        let customTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tags[tagIndex].items[itemIndex].title = customTitle
        tags[tagIndex].items[itemIndex].titleIsCustom = !customTitle.isEmpty
        save()
    }

    func deleteItem(tagIndex: Int, itemIndex: Int) {
        guard tags.indices.contains(tagIndex), tags[tagIndex].items.indices.contains(itemIndex) else { return }
        removeImageFileIfNeeded(tags[tagIndex].items.remove(at: itemIndex))
        save()
    }

    func image(for item: ClipItem) -> NSImage? {
        guard item.isImage, let fileName = item.imageFileName else { return nil }
        return NSImage(contentsOf: imageDirectory.appendingPathComponent(fileName))
    }

    func imageData(for item: ClipItem) -> Data? {
        guard item.isImage, let fileName = item.imageFileName else { return nil }
        return try? Data(contentsOf: imageDirectory.appendingPathComponent(fileName))
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func removeImageFileIfNeeded(_ item: ClipItem) {
        guard item.isImage, let fileName = item.imageFileName else { return }
        try? FileManager.default.removeItem(at: imageDirectory.appendingPathComponent(fileName))
    }

    func displayText(for item: ClipItem, in tag: ClipTag) -> String {
        if !tag.isRecent, item.hasCustomTitle {
            return singleLinePreview(item.title)
        }
        if item.isImage {
            guard let data = imageData(for: item), let bitmap = NSBitmapImageRep(data: data) else { return "图片" }
            return "图片 \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)"
        }
        return singleLinePreview(item.content)
    }

    func displayToolTip(for item: ClipItem, in tag: ClipTag) -> String {
        if item.isImage { return displayText(for: item, in: tag) }
        return item.content
    }

    private func singleLinePreview(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "  ↵  ")
            .replacingOccurrences(of: "\n", with: "  ↵  ")
            .replacingOccurrences(of: "\r", with: "  ↵  ")
            .replacingOccurrences(of: "\t", with: "  ")
    }
}

final class PickerPanel: NSPanel {
    weak var keyHandler: PickerController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyHandler?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }
}

final class PickerRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 4, dy: 2)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
    }
}

final class PickerChromeView: NSView {
    static let chromeInset: CGFloat = 0
    let chromeInset = PickerChromeView.chromeInset
}

final class PickerEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSurfaceColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurfaceColor()
    }

    private func updateSurfaceColor() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = isDark
            ? NSColor.black.withAlphaComponent(0.24).cgColor
            : NSColor.white.withAlphaComponent(0.78).cgColor
    }
}

final class PickerController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let store: ClipStore
    let panel: PickerPanel
    private let segmented: NSSegmentedControl
    private let tableView = NSTableView()
    private let guideView = NSView()
    private let guideIcon = NSImageView()
    private let guideTitle = NSTextField(labelWithString: "Ctrl+V 已打开 ClipNest")
    private let guideDetail = NSTextField(labelWithString: "↑↓ 选择，Return 粘贴；⌘V 仍然直接粘贴")
    private let emptyLabel = NSTextField(labelWithString: "先复制一段文字、链接或图片")
    private var guideHeightConstraint: NSLayoutConstraint!
    private var guideSpacingConstraint: NSLayoutConstraint!
    private var shouldShowGuide = false
    private var selectedTagIndex = 0
    private var previousApplication: NSRunningApplication?
    private var previousFocusedElement: AXUIElement?
    private var inputAnchorFrame: CGRect?
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private(set) var diagnosticPreparation = "not-attempted"
    private(set) var diagnosticShowCount = 0
    private(set) var diagnosticHideCount = 0
    private(set) var diagnosticLastHideReason = "none"
    var onPaste: ((ClipItem, NSRunningApplication?, AXUIElement?) -> Void)?

    init(store: ClipStore) {
        self.store = store
        panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 266),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        segmented = NSSegmentedControl(labels: ["最近"], trackingMode: .selectOne, target: nil, action: nil)
        super.init()
        configurePanel()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .clipStoreDidChange, object: store)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
    }

    private func configurePanel() {
        panel.keyHandler = self
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        let chrome = PickerChromeView()
        let effect = PickerEffectView()
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.4
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.38).cgColor
        chrome.addSubview(effect)
        panel.contentView = chrome
        NSLayoutConstraint.activate([
            effect.topAnchor.constraint(equalTo: chrome.topAnchor, constant: chrome.chromeInset),
            effect.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: chrome.chromeInset),
            effect.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -chrome.chromeInset),
            effect.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -chrome.chromeInset)
        ])

        guideView.translatesAutoresizingMaskIntoConstraints = false
        guideView.wantsLayer = true
        guideView.layer?.cornerRadius = 12
        guideView.layer?.cornerCurve = .continuous
        guideView.layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.34).cgColor

        guideIcon.translatesAutoresizingMaskIntoConstraints = false
        guideIcon.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        guideIcon.contentTintColor = .secondaryLabelColor
        guideIcon.imageScaling = .scaleProportionallyDown

        guideTitle.translatesAutoresizingMaskIntoConstraints = false
        guideTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        guideTitle.textColor = .labelColor
        guideDetail.translatesAutoresizingMaskIntoConstraints = false
        guideDetail.font = .systemFont(ofSize: 10.5)
        guideDetail.textColor = .secondaryLabelColor

        guideView.addSubview(guideIcon)
        guideView.addSubview(guideTitle)
        guideView.addSubview(guideDetail)
        NSLayoutConstraint.activate([
            guideIcon.leadingAnchor.constraint(equalTo: guideView.leadingAnchor, constant: 11),
            guideIcon.centerYAnchor.constraint(equalTo: guideView.centerYAnchor),
            guideIcon.widthAnchor.constraint(equalToConstant: 24),
            guideIcon.heightAnchor.constraint(equalToConstant: 24),
            guideTitle.leadingAnchor.constraint(equalTo: guideIcon.trailingAnchor, constant: 9),
            guideTitle.topAnchor.constraint(equalTo: guideView.topAnchor, constant: 7),
            guideTitle.trailingAnchor.constraint(equalTo: guideView.trailingAnchor, constant: -10),
            guideDetail.leadingAnchor.constraint(equalTo: guideTitle.leadingAnchor),
            guideDetail.topAnchor.constraint(equalTo: guideTitle.bottomAnchor, constant: 1),
            guideDetail.trailingAnchor.constraint(equalTo: guideView.trailingAnchor, constant: -10)
        ])

        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.segmentStyle = .rounded
        segmented.controlSize = .small
        segmented.focusRingType = .none
        segmented.target = self
        segmented.action = #selector(segmentChanged)

        let divider = NSBox()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.boxType = .separator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        let rowHeight: CGFloat = 39
        let rowSpacing: CGFloat = 1
        let visibleRowCount: CGFloat = 5
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(clickedRow)
        tableView.focusRingType = .none

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 12.5)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center

        effect.addSubview(guideView)
        effect.addSubview(segmented)
        effect.addSubview(divider)
        effect.addSubview(scroll)
        effect.addSubview(emptyLabel)

        guideHeightConstraint = guideView.heightAnchor.constraint(equalToConstant: 0)
        guideSpacingConstraint = segmented.topAnchor.constraint(equalTo: guideView.bottomAnchor)

        NSLayoutConstraint.activate([
            guideView.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            guideView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            guideView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            guideHeightConstraint,

            guideSpacingConstraint,
            segmented.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            segmented.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            segmented.heightAnchor.constraint(equalToConstant: 28),

            divider.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 9),
            divider.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
            scroll.heightAnchor.constraint(equalToConstant: rowHeight * visibleRowCount + rowSpacing * (visibleRowCount - 1)),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -11),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -16)
        ])
        updateGuideLayout(animated: false)
    }

    @objc private func storeChanged() {
        reload()
    }

    func prepareForFocusedInput() -> Bool {
        guard let context = focusedInputContext() else {
            diagnosticPreparation = "focused-input-not-found"
            return false
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        previousFocusedElement = context.element
        inputAnchorFrame = context.frame
        diagnosticPreparation = "success:\(Int(context.frame.minX)),\(Int(context.frame.minY)),\(Int(context.frame.width)),\(Int(context.frame.height))"
        return true
    }

    func prepareFallback() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        previousFocusedElement = nil
        inputAnchorFrame = nil
        diagnosticPreparation = "fallback-near-pointer"
    }

    func showPrepared(showGuide: Bool = false) {
        diagnosticShowCount += 1
        store.recordPasteboard(NSPasteboard.general)
        shouldShowGuide = showGuide && !UserDefaults.standard.bool(forKey: "ClipNest.didCompleteQuickPasteGuide.v1")
        updateGuideLayout(animated: false)
        resetToRecentFirstItem()
        positionNearInput()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        panel.makeFirstResponder(tableView)
        resetToRecentFirstItem()
        installInteractionMonitors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let status = "visible=\(self.panel.isVisible) key=\(self.panel.isKeyWindow) showCount=\(self.diagnosticShowCount) hideCount=\(self.diagnosticHideCount) reason=\(self.diagnosticLastHideReason)\n"
            try? status.write(
                to: URL(fileURLWithPath: "/private/tmp/clipnest-panel-status.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    func showFromMenu() {
        if prepareForFocusedInput() {
            showPrepared()
            return
        }
        prepareFallback()
        showPrepared()
    }

    func hide() {
        diagnosticHideCount += 1
        removeInteractionMonitors()
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    private func installInteractionMonitors() {
        removeInteractionMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            return self.handleKey(event) ? nil : event
        }

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.hide()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.panel.isVisible else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
    }

    private func removeInteractionMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    func confirmSelection() {
        pasteSelected()
    }

    private func reload() {
        let labels = store.tags.map(\.name)
        segmented.segmentCount = labels.count
        for (index, label) in labels.enumerated() {
            segmented.setLabel(label, forSegment: index)
        }
        selectedTagIndex = min(selectedTagIndex, max(0, labels.count - 1))
        segmented.selectedSegment = selectedTagIndex
        tableView.reloadData()
        emptyLabel.isHidden = numberOfRows(in: tableView) > 0
        if numberOfRows(in: tableView) > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateRowAppearance()
    }

    private func updateGuideLayout(animated: Bool) {
        guideView.isHidden = !shouldShowGuide
        guideHeightConstraint.constant = shouldShowGuide ? 52 : 0
        guideSpacingConstraint.constant = shouldShowGuide ? 8 : 0
        let targetHeight: CGFloat = shouldShowGuide ? 326 : 266
        var frame = panel.frame
        frame.origin.y += frame.height - targetHeight
        frame.size.height = targetHeight
        if animated {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.invalidateShadow()
    }

    private func resetToRecentFirstItem() {
        selectedTagIndex = store.tags.firstIndex(where: { $0.isRecent }) ?? 0
        reload()
        guard numberOfRows(in: tableView) > 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
        if let scrollView = tableView.enclosingScrollView {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func focusedInputContext() -> (element: AXUIElement, frame: CGRect)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else { return nil }

        let element = focusedValue as! AXUIElement
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else { return nil }
        let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        guard editableRoles.contains(role) else { return nil }

        var subroleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String,
           subrole == "AXSecureTextField" {
            return nil
        }

        guard let accessibilityFrame = accessibilityFrame(of: element) else { return nil }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitFrame = CGRect(
            x: accessibilityFrame.minX,
            y: primaryTop - accessibilityFrame.maxY,
            width: accessibilityFrame.width,
            height: accessibilityFrame.height
        )
        guard appKitFrame.width > 1, appKitFrame.height > 1 else { return nil }
        return (element, appKitFrame)
    }

    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func positionNearInput() {
        guard let anchor = inputAnchorFrame else {
            positionNearPointer()
            return
        }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let gap: CGFloat = 8
        var x = anchor.minX - PickerChromeView.chromeInset
        var y = anchor.maxY + gap

        if y + size.height > visibleFrame.maxY {
            y = anchor.minY - size.height - gap
        }
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        y = min(max(y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionNearPointer() {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var x = point.x - 36 - PickerChromeView.chromeInset
        var y = point.y - size.height - 12
        if y < visibleFrame.minY { y = point.y + 12 }
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        y = min(max(y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func segmentChanged() {
        selectedTagIndex = max(0, segmented.selectedSegment)
        tableView.reloadData()
        emptyLabel.isHidden = numberOfRows(in: tableView) > 0
        if numberOfRows(in: tableView) > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateRowAppearance()
    }

    @objc private func clickedRow() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        selectRow(row)
        pasteSelected()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard store.tags.indices.contains(selectedTagIndex) else { return 0 }
        return store.tags[selectedTagIndex].items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard store.tags.indices.contains(selectedTagIndex), store.tags[selectedTagIndex].items.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ClipCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            cell.wantsLayer = true
            cell.layer?.masksToBounds = true
            let indexLabel = NSTextField(labelWithString: "")
            indexLabel.identifier = NSUserInterfaceItemIdentifier("ClipIndex")
            indexLabel.translatesAutoresizingMaskIntoConstraints = false
            indexLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            indexLabel.textColor = .tertiaryLabelColor
            indexLabel.alignment = .right
            let thumbnail = NSImageView()
            thumbnail.translatesAutoresizingMaskIntoConstraints = false
            thumbnail.imageScaling = .scaleProportionallyUpOrDown
            thumbnail.wantsLayer = true
            thumbnail.layer?.cornerRadius = 4
            thumbnail.layer?.masksToBounds = true
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
            label.font = .systemFont(ofSize: 14)
            cell.imageView = thumbnail
            cell.textField = label
            cell.addSubview(indexLabel)
            cell.addSubview(thumbnail)
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                indexLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
                indexLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                indexLabel.widthAnchor.constraint(equalToConstant: 17),
                thumbnail.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                thumbnail.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                thumbnail.widthAnchor.constraint(equalToConstant: 24),
                thumbnail.heightAnchor.constraint(equalToConstant: 24),
                label.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 9),
                label.trailingAnchor.constraint(equalTo: indexLabel.leadingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        let item = store.tags[selectedTagIndex].items[row]
        let tag = store.tags[selectedTagIndex]
        if let indexLabel = cell.subviews.first(where: { $0.identifier?.rawValue == "ClipIndex" }) as? NSTextField {
            indexLabel.stringValue = row < 5 ? "\(row + 1)" : ""
        }
        cell.textField?.stringValue = store.displayText(for: item, in: tag)
        cell.imageView?.image = item.isImage
            ? store.image(for: item)
            : NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        cell.toolTip = store.displayToolTip(for: item, in: tag)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PickerRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRowAppearance()
    }

    private func updateRowAppearance() {
        let selectedRow = tableView.selectedRow
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { continue }
            let isSelected = row == selectedRow
            cell.textField?.textColor = isSelected ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor
            if let indexLabel = cell.subviews.first(where: { $0.identifier?.rawValue == "ClipIndex" }) as? NSTextField {
                indexLabel.textColor = isSelected
                    ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.78)
                    : .tertiaryLabelColor
            }
            if cell.imageView?.image?.isTemplate == true {
                cell.imageView?.contentTintColor = isSelected ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor
            } else {
                cell.imageView?.contentTintColor = nil
            }
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            selectTag(selectedTagIndex - 1)
        case 124:
            selectTag(selectedTagIndex + 1)
        case 125:
            selectRow(tableView.selectedRow + 1)
        case 126:
            selectRow(tableView.selectedRow - 1)
        case 36, 76:
            pasteSelected()
        case 53:
            cancelSelection()
        default:
            if let character = event.charactersIgnoringModifiers?.first,
               let number = Int(String(character)), number >= 1, number <= 5 {
                selectRow(number - 1)
                pasteSelected()
            } else {
                return false
            }
        }
        return true
    }

    func cancelSelection() {
        hide()
        previousApplication?.activate(options: [.activateIgnoringOtherApps])
        if let previousFocusedElement {
            AXUIElementSetAttributeValue(previousFocusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private func selectTag(_ index: Int) {
        guard !store.tags.isEmpty else { return }
        selectedTagIndex = min(max(index, 0), store.tags.count - 1)
        segmented.selectedSegment = selectedTagIndex
        tableView.reloadData()
        emptyLabel.isHidden = numberOfRows(in: tableView) > 0
        selectRow(0)
    }

    private func selectRow(_ index: Int) {
        let count = numberOfRows(in: tableView)
        guard count > 0 else { return }
        let row = min(max(index, 0), count - 1)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        updateRowAppearance()
    }

    private func pasteSelected() {
        guard store.tags.indices.contains(selectedTagIndex) else { return }
        let row = max(0, tableView.selectedRow)
        guard store.tags[selectedTagIndex].items.indices.contains(row) else { return }
        let item = store.tags[selectedTagIndex].items[row]
        if shouldShowGuide {
            UserDefaults.standard.set(true, forKey: "ClipNest.didCompleteQuickPasteGuide.v1")
            shouldShowGuide = false
        }
        hide()
        onPaste?(item, previousApplication, previousFocusedElement)
    }

    func windowDidResignKey(_ notification: Notification) {
        diagnosticLastHideReason = "window-resigned-key"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.hide()
        }
    }

    @objc private func applicationDidResignActive() {
        guard panel.isVisible else { return }
        diagnosticLastHideReason = "application-resigned-active"
        hide()
    }
}

final class SettingsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.22).cgColor
        layer?.borderWidth = 0
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.22).cgColor
    }
}

final class SettingsItemRowView: NSTableRowView {
    override func drawSeparator(in dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.42).setFill()
        NSRect(x: 55, y: 0, width: max(0, bounds.width - 67), height: 0.5).fill()
    }
}

final class ManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ClipStore
    private let tagTable = NSTableView()
    private let itemTable = NSTableView()
    private let tagTitle = NSTextField(labelWithString: "最近")
    private let permissionBanner = NSBox()
    private let permissionIcon = NSImageView()
    private let permissionTitle = NSTextField(labelWithString: "正在检查辅助功能权限…")
    private let permissionHelp = NSTextField(labelWithString: "")
    private let openPermissionButton = NSButton(title: "打开权限", target: nil, action: nil)
    private let revealApplicationButton = NSButton(title: "显示 App", target: nil, action: nil)
    private let addItemButton = NSButton(title: "添加剪贴板", target: nil, action: nil)
    private let editItemButton = NSButton(title: "编辑", target: nil, action: nil)
    private let deleteItemButton = NSButton(title: "删除", target: nil, action: nil)
    private let emptyManagerLabel = NSTextField(labelWithString: "此标签还没有内容")
    private var selectedTagIndex = 0
    private var isReloading = false
    var onOpenPermissionSettings: (() -> Void)?
    var onRevealApplication: (() -> Void)?
    var monitoringStatus: (() -> Bool)?

    init(store: ClipStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipNest"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.setFrameAutosaveName("ClipNestManagerV2")
        super.init(window: window)
        configureContent()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .clipStoreDidChange, object: store)
    }

    required init?(coder: NSCoder) { nil }

    private func configureContent() {
        guard let content = window?.contentView else { return }

        let split = NSSplitView()
        split.translatesAutoresizingMaskIntoConstraints = false
        split.isVertical = true
        split.dividerStyle = .thin

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        let detail = NSView()
        detail.wantsLayer = true
        detail.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(detail)
        split.setPosition(220, ofDividerAt: 0)
        content.addSubview(split)

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])

        configureSidebar(sidebar)
        configureDetail(detail)
        reloadAll()
    }

    private func configureSidebar(_ sidebar: NSView) {
        let appIcon = NSImageView()
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: nil)
        appIcon.contentTintColor = .controlAccentColor
        let appName = NSTextField(labelWithString: "ClipNest")
        appName.font = .systemFont(ofSize: 15, weight: .semibold)
        let brand = NSStackView(views: [appIcon, appName])
        brand.translatesAutoresizingMaskIntoConstraints = false
        brand.orientation = .horizontal
        brand.spacing = 8

        let heading = NSTextField(labelWithString: "标签")
        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let addTag = NSButton(title: "+", target: self, action: #selector(addTag))
        let deleteTag = NSButton(title: "−", target: self, action: #selector(deleteTag))
        for button in [addTag, deleteTag] {
            button.bezelStyle = .texturedRounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 14, weight: .medium)
        }
        addTag.toolTip = "新建标签"
        deleteTag.toolTip = "删除标签"
        let tagButtons = NSStackView(views: [addTag, deleteTag])
        tagButtons.translatesAutoresizingMaskIntoConstraints = false
        tagButtons.orientation = .horizontal
        tagButtons.spacing = 4

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tag"))
        tagTable.addTableColumn(column)
        tagTable.headerView = nil
        tagTable.rowHeight = 32
        tagTable.intercellSpacing = NSSize(width: 0, height: 2)
        tagTable.backgroundColor = .clear
        tagTable.dataSource = self
        tagTable.delegate = self
        tagTable.style = .sourceList

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tagTable
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        sidebar.addSubview(brand)
        sidebar.addSubview(heading)
        sidebar.addSubview(tagButtons)
        sidebar.addSubview(scroll)
        NSLayoutConstraint.activate([
            appIcon.widthAnchor.constraint(equalToConstant: 22),
            appIcon.heightAnchor.constraint(equalToConstant: 22),
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 52),
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),

            heading.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 22),
            heading.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            tagButtons.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            tagButtons.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12)
        ])
    }

    private func configureDetail(_ detail: NSView) {
        permissionBanner.translatesAutoresizingMaskIntoConstraints = false
        permissionBanner.boxType = .custom
        permissionBanner.cornerRadius = 12
        permissionBanner.borderWidth = 0
        permissionBanner.fillColor = NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.22)

        permissionIcon.translatesAutoresizingMaskIntoConstraints = false
        permissionIcon.imageScaling = .scaleProportionallyDown

        permissionTitle.translatesAutoresizingMaskIntoConstraints = false
        permissionTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        permissionHelp.translatesAutoresizingMaskIntoConstraints = false
        permissionHelp.font = .systemFont(ofSize: 11.5)
        permissionHelp.textColor = .secondaryLabelColor
        permissionHelp.lineBreakMode = .byWordWrapping
        permissionHelp.maximumNumberOfLines = 2

        openPermissionButton.target = self
        openPermissionButton.action = #selector(openPermissionSettings)
        revealApplicationButton.target = self
        revealApplicationButton.action = #selector(revealApplication)
        openPermissionButton.bezelStyle = .rounded
        revealApplicationButton.bezelStyle = .rounded
        openPermissionButton.controlSize = .small
        revealApplicationButton.controlSize = .small
        let permissionButtons = NSStackView(views: [openPermissionButton, revealApplicationButton])
        permissionButtons.translatesAutoresizingMaskIntoConstraints = false
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 6

        guard let permissionContent = permissionBanner.contentView else { return }
        permissionContent.addSubview(permissionIcon)
        permissionContent.addSubview(permissionTitle)
        permissionContent.addSubview(permissionHelp)
        permissionContent.addSubview(permissionButtons)
        NSLayoutConstraint.activate([
            permissionIcon.leadingAnchor.constraint(equalTo: permissionContent.leadingAnchor, constant: 14),
            permissionIcon.centerYAnchor.constraint(equalTo: permissionContent.centerYAnchor),
            permissionIcon.widthAnchor.constraint(equalToConstant: 28),
            permissionIcon.heightAnchor.constraint(equalToConstant: 28),
            permissionTitle.topAnchor.constraint(equalTo: permissionContent.topAnchor, constant: 12),
            permissionTitle.leadingAnchor.constraint(equalTo: permissionIcon.trailingAnchor, constant: 11),
            permissionTitle.trailingAnchor.constraint(lessThanOrEqualTo: permissionButtons.leadingAnchor, constant: -12),
            permissionHelp.topAnchor.constraint(equalTo: permissionTitle.bottomAnchor, constant: 3),
            permissionHelp.leadingAnchor.constraint(equalTo: permissionTitle.leadingAnchor),
            permissionHelp.trailingAnchor.constraint(equalTo: permissionButtons.leadingAnchor, constant: -12),
            permissionHelp.bottomAnchor.constraint(lessThanOrEqualTo: permissionContent.bottomAnchor, constant: -11),
            permissionButtons.centerYAnchor.constraint(equalTo: permissionContent.centerYAnchor),
            permissionButtons.trailingAnchor.constraint(equalTo: permissionContent.trailingAnchor, constant: -10)
        ])

        tagTitle.translatesAutoresizingMaskIntoConstraints = false
        tagTitle.font = .systemFont(ofSize: 26, weight: .bold)

        addItemButton.target = self
        addItemButton.action = #selector(addClipboardItem)
        editItemButton.target = self
        editItemButton.action = #selector(editItem)
        deleteItemButton.target = self
        deleteItemButton.action = #selector(deleteItem)
        for button in [addItemButton, editItemButton, deleteItemButton] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
        }
        let buttons = NSStackView(views: [addItemButton, editItemButton, deleteItemButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        itemTable.addTableColumn(column)
        itemTable.headerView = nil
        itemTable.rowHeight = 52
        itemTable.intercellSpacing = NSSize(width: 0, height: 0)
        itemTable.backgroundColor = .clear
        itemTable.selectionHighlightStyle = .regular
        itemTable.dataSource = self
        itemTable.delegate = self
        itemTable.doubleAction = #selector(editItem)
        itemTable.target = self

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = itemTable
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let listCard = SettingsCardView()
        listCard.translatesAutoresizingMaskIntoConstraints = false
        listCard.addSubview(scroll)

        emptyManagerLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyManagerLabel.font = .systemFont(ofSize: 13)
        emptyManagerLabel.textColor = .tertiaryLabelColor
        emptyManagerLabel.alignment = .center
        listCard.addSubview(emptyManagerLabel)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: listCard.topAnchor, constant: 1),
            scroll.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: -1),
            scroll.bottomAnchor.constraint(equalTo: listCard.bottomAnchor, constant: -1),
            emptyManagerLabel.centerXAnchor.constraint(equalTo: listCard.centerXAnchor),
            emptyManagerLabel.centerYAnchor.constraint(equalTo: listCard.centerYAnchor)
        ])

        detail.addSubview(permissionBanner)
        detail.addSubview(tagTitle)
        detail.addSubview(buttons)
        detail.addSubview(listCard)
        NSLayoutConstraint.activate([
            permissionBanner.topAnchor.constraint(equalTo: detail.topAnchor, constant: 56),
            permissionBanner.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 28),
            permissionBanner.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -28),
            permissionBanner.heightAnchor.constraint(equalToConstant: 76),
            tagTitle.topAnchor.constraint(equalTo: permissionBanner.bottomAnchor, constant: 26),
            tagTitle.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 28),
            buttons.centerYAnchor.constraint(equalTo: tagTitle.centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -28),
            listCard.topAnchor.constraint(equalTo: tagTitle.bottomAnchor, constant: 18),
            listCard.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 28),
            listCard.trailingAnchor.constraint(equalTo: detail.trailingAnchor, constant: -28),
            listCard.bottomAnchor.constraint(equalTo: detail.bottomAnchor, constant: -28)
        ])
        updatePermissionStatus(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            monitoring: false
        )
    }

    func updatePermissionStatus(accessibility: Bool, inputMonitoring: Bool, monitoring: Bool) {
        guard isWindowLoaded else { return }
        if accessibility && monitoring {
            permissionTitle.stringValue = "已就绪：Ctrl+V 快速面板已启用"
            permissionHelp.stringValue = "⌘V 保持系统粘贴；按 Ctrl+V 打开 ClipNest，Return 粘贴。"
            permissionIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            permissionIcon.contentTintColor = .systemGreen
            permissionBanner.fillColor = NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.22)
            openPermissionButton.isHidden = true
            revealApplicationButton.isHidden = true
        } else {
            if !accessibility {
                permissionTitle.stringValue = "第一次按 Ctrl+V：还差一步授权"
                permissionHelp.stringValue = "允许辅助功能后，ClipNest 才能定位输入框并把选中内容粘贴回去。"
                openPermissionButton.title = "打开辅助功能"
            } else {
                permissionTitle.stringValue = "Ctrl+V 快捷键暂时不可用"
                permissionHelp.stringValue = inputMonitoring
                    ? "请退出并重新打开 ClipNest；⌘V 不受影响。"
                    : "当前快捷键被其他 App 占用；⌘V 不受影响。"
                openPermissionButton.title = "检查权限"
            }
            permissionIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            permissionIcon.contentTintColor = .systemOrange
            permissionBanner.fillColor = NSColor.systemOrange.withAlphaComponent(0.08)
            openPermissionButton.isHidden = false
            revealApplicationButton.isHidden = false
        }
    }

    func showManager() {
        selectedTagIndex = store.tags.firstIndex(where: { $0.isRecent }) ?? 0
        reloadAll()
        if store.tags.indices.contains(selectedTagIndex) {
            tagTable.selectRowIndexes(IndexSet(integer: selectedTagIndex), byExtendingSelection: false)
            itemTable.reloadData()
            if !store.tags[selectedTagIndex].items.isEmpty {
                itemTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                itemTable.scrollRowToVisible(0)
            }
            updateDetailState()
        }
        updatePermissionStatus(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            monitoring: monitoringStatus?() ?? false
        )
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func storeChanged() { reloadAll() }

    private func reloadAll() {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }
        selectedTagIndex = min(selectedTagIndex, max(0, store.tags.count - 1))
        tagTable.reloadData()
        itemTable.reloadData()
        emptyManagerLabel.isHidden = numberOfRows(in: itemTable) > 0
        if !store.tags.isEmpty {
            if tagTable.selectedRow != selectedTagIndex {
                tagTable.selectRowIndexes(IndexSet(integer: selectedTagIndex), byExtendingSelection: false)
            }
            updateDetailState()
        }
    }

    private func updateDetailState() {
        guard store.tags.indices.contains(selectedTagIndex) else { return }
        tagTitle.stringValue = store.tags[selectedTagIndex].name
        let recent = store.tags[selectedTagIndex].isRecent
        addItemButton.title = recent ? "添加到标签…" : "添加剪贴板"
        addItemButton.isEnabled = recent ? itemTable.selectedRow >= 0 : true
        editItemButton.isEnabled = !recent && itemTable.selectedRow >= 0
        deleteItemButton.isEnabled = !recent && itemTable.selectedRow >= 0
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === tagTable { return store.tags.count }
        guard store.tags.indices.contains(selectedTagIndex) else { return 0 }
        return store.tags[selectedTagIndex].items.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView === itemTable ? SettingsItemRowView() : nil
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === tagTable {
            let identifier = NSUserInterfaceItemIdentifier("TagCell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.imageScaling = .scaleProportionallyDown
                icon.contentTintColor = .secondaryLabelColor
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                label.font = .systemFont(ofSize: 13, weight: .medium)
                label.lineBreakMode = .byTruncatingTail
                let count = NSTextField(labelWithString: "")
                count.identifier = NSUserInterfaceItemIdentifier("TagCount")
                count.translatesAutoresizingMaskIntoConstraints = false
                count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                count.textColor = .secondaryLabelColor
                count.alignment = .right
                cell.imageView = icon
                cell.textField = label
                cell.addSubview(icon)
                cell.addSubview(label)
                cell.addSubview(count)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 17),
                    icon.heightAnchor.constraint(equalToConstant: 17),
                    label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -8),
                    count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                    count.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    count.widthAnchor.constraint(greaterThanOrEqualToConstant: 24)
                ])
            }
            let tag = store.tags[row]
            cell.textField?.stringValue = tag.name
            cell.imageView?.image = NSImage(
                systemSymbolName: tag.isRecent ? "clock.arrow.circlepath" : "folder",
                accessibilityDescription: nil
            )
            if let count = cell.subviews.first(where: { $0.identifier?.rawValue == "TagCount" }) as? NSTextField {
                count.stringValue = "\(tag.items.count)"
            }
            return cell
        }

        let identifier = NSUserInterfaceItemIdentifier("ItemCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let thumbnail = NSImageView()
            thumbnail.translatesAutoresizingMaskIntoConstraints = false
            thumbnail.imageScaling = .scaleProportionallyUpOrDown
            thumbnail.wantsLayer = true
            thumbnail.layer?.cornerRadius = 5
            thumbnail.layer?.cornerCurve = .continuous
            thumbnail.layer?.masksToBounds = true
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 13.5, weight: .medium)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
            let subtitle = NSTextField(labelWithString: "")
            subtitle.identifier = NSUserInterfaceItemIdentifier("ItemSubtitle")
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            subtitle.font = .systemFont(ofSize: 11.5)
            subtitle.textColor = .secondaryLabelColor
            subtitle.lineBreakMode = .byTruncatingTail
            subtitle.maximumNumberOfLines = 1
            subtitle.cell?.usesSingleLineMode = true
            subtitle.cell?.truncatesLastVisibleLine = true
            cell.imageView = thumbnail
            cell.textField = label
            cell.addSubview(thumbnail)
            cell.addSubview(label)
            cell.addSubview(subtitle)
            NSLayoutConstraint.activate([
                thumbnail.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                thumbnail.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                thumbnail.widthAnchor.constraint(equalToConstant: 32),
                thumbnail.heightAnchor.constraint(equalToConstant: 32),
                label.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 11),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
                subtitle.leadingAnchor.constraint(equalTo: label.leadingAnchor),
                subtitle.trailingAnchor.constraint(equalTo: label.trailingAnchor),
                subtitle.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2)
            ])
        }
        let tag = store.tags[selectedTagIndex]
        let item = store.tags[selectedTagIndex].items[row]
        cell.textField?.stringValue = store.displayText(for: item, in: tag)
        cell.imageView?.image = item.isImage
            ? store.image(for: item)
            : NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        if let subtitle = cell.subviews.first(where: { $0.identifier?.rawValue == "ItemSubtitle" }) as? NSTextField {
            if item.isImage {
                subtitle.stringValue = item.hasCustomTitle && !tag.isRecent ? "图片" : "本地图片"
            } else if item.hasCustomTitle && !tag.isRecent {
                subtitle.stringValue = compactManagerPreview(item.content)
            } else {
                subtitle.stringValue = "文本"
            }
        }
        cell.toolTip = store.displayToolTip(for: item, in: tag)
        return cell
    }

    private func compactManagerPreview(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "  ↵  ")
            .replacingOccurrences(of: "\n", with: "  ↵  ")
            .replacingOccurrences(of: "\r", with: "  ↵  ")
            .replacingOccurrences(of: "\t", with: "  ")
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
        if notification.object as? NSTableView === tagTable, tagTable.selectedRow >= 0 {
            selectedTagIndex = tagTable.selectedRow
            itemTable.reloadData()
            emptyManagerLabel.isHidden = numberOfRows(in: itemTable) > 0
        }
        updateDetailState()
    }

    @objc private func addTag() {
        guard let name = prompt(title: "新建标签", message: "标签名称", defaultValue: "") else { return }
        store.addTag(named: name)
        selectedTagIndex = max(0, store.tags.count - 1)
        reloadAll()
    }

    @objc private func deleteTag() {
        guard store.tags.indices.contains(selectedTagIndex), !store.tags[selectedTagIndex].isRecent else { return }
        store.deleteTag(at: selectedTagIndex)
        selectedTagIndex = max(0, selectedTagIndex - 1)
        reloadAll()
    }

    @objc private func addClipboardItem() {
        guard store.tags.indices.contains(selectedTagIndex) else { return }
        if store.tags[selectedTagIndex].isRecent {
            showMoveToTagMenu()
            return
        }
        let pasteboard = NSPasteboard.general
        if let image = store.image(from: pasteboard) {
            store.addImageItem(to: selectedTagIndex, image: image)
        } else if let content = pasteboard.string(forType: .string), !content.isEmpty {
            store.addItem(to: selectedTagIndex, title: "", content: content)
        }
    }

    private func showMoveToTagMenu() {
        let row = itemTable.selectedRow
        guard row >= 0,
              store.tags.indices.contains(selectedTagIndex),
              store.tags[selectedTagIndex].items.indices.contains(row) else { return }

        let menu = NSMenu(title: "添加到标签")
        for tag in store.tags where !tag.isRecent {
            let item = NSMenuItem(title: tag.name, action: #selector(moveRecentItemToTag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tag.id
            menu.addItem(item)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let createItem = NSMenuItem(title: "新建标签…", action: #selector(moveRecentItemToNewTag), keyEquivalent: "")
        createItem.target = self
        menu.addItem(createItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: addItemButton.bounds.height + 3), in: addItemButton)
    }

    @objc private func moveRecentItemToTag(_ sender: NSMenuItem) {
        guard let tagID = sender.representedObject as? String else { return }
        moveSelectedRecentItem(toTagID: tagID)
    }

    @objc private func moveRecentItemToNewTag() {
        guard let name = prompt(title: "新建标签", message: "创建后会把当前条目移入该标签", defaultValue: ""),
              let tagID = store.addTag(named: name) else { return }
        moveSelectedRecentItem(toTagID: tagID)
    }

    private func moveSelectedRecentItem(toTagID tagID: String) {
        let row = itemTable.selectedRow
        guard row >= 0,
              store.tags.indices.contains(selectedTagIndex),
              store.tags[selectedTagIndex].isRecent,
              store.tags[selectedTagIndex].items.indices.contains(row) else { return }
        let itemID = store.tags[selectedTagIndex].items[row].id
        guard store.moveRecentItem(itemID: itemID, toTagID: tagID) else { return }
        let remainingCount = store.tags[selectedTagIndex].items.count
        if remainingCount > 0 {
            let nextRow = min(row, remainingCount - 1)
            itemTable.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        }
        updateDetailState()
    }

    @objc private func editItem() {
        let row = itemTable.selectedRow
        guard store.tags.indices.contains(selectedTagIndex), store.tags[selectedTagIndex].items.indices.contains(row), !store.tags[selectedTagIndex].isRecent else { return }
        let item = store.tags[selectedTagIndex].items[row]
        if item.isImage {
            let currentTitle = item.hasCustomTitle ? item.title : ""
            guard let title = prompt(title: "编辑图片名称", message: "留空则恢复默认图片信息", defaultValue: currentTitle) else { return }
            store.updateItemTitle(tagIndex: selectedTagIndex, itemIndex: row, title: title)
            return
        }
        guard let result = editPrompt(item: item) else { return }
        store.updateItem(tagIndex: selectedTagIndex, itemIndex: row, title: result.0, content: result.1)
    }

    @objc private func deleteItem() {
        let row = itemTable.selectedRow
        guard row >= 0 else { return }
        store.deleteItem(tagIndex: selectedTagIndex, itemIndex: row)
    }

    @objc private func openPermissionSettings() {
        onOpenPermissionSettings?()
    }

    @objc private func revealApplication() {
        onRevealApplication?()
    }

    private func prompt(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func editPrompt(item: ClipItem) -> (String, String)? {
        let alert = NSAlert()
        alert.messageText = "编辑内容"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 86))
        let titleField = NSTextField(string: item.hasCustomTitle ? item.title : "")
        let contentField = NSTextField(string: item.content)
        titleField.frame = NSRect(x: 0, y: 50, width: 420, height: 24)
        contentField.frame = NSRect(x: 0, y: 10, width: 420, height: 24)
        titleField.placeholderString = "自定义名称（可留空）"
        contentField.placeholderString = "内容"
        view.addSubview(titleField)
        view.addSubview(contentField)
        alert.accessoryView = view
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (titleField.stringValue, contentField.stringValue)
    }
}

private let clipNestEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let runtime = Unmanaged<GlobalShortcutRuntime>.fromOpaque(userInfo).takeUnretainedValue()
    return runtime.handle(type: type, event: event)
}

private let clipNestHotKeyCallback: EventHandlerUPP = { _, event, userInfo in
    guard let event, let userInfo else { return OSStatus(eventNotHandledErr) }
    let runtime = Unmanaged<GlobalShortcutRuntime>.fromOpaque(userInfo).takeUnretainedValue()
    return runtime.handleHotKey(event)
}

final class GlobalShortcutRuntime {
    private let picker: PickerController
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventThread: Thread?
    private var hotKeyHandler: EventHandlerRef?
    private var controlVHotKey: EventHotKeyRef?
    private var capturedV = false
    private var synthesizingPaste = false
    var onPermissionChanged: ((Bool, Bool, Bool) -> Void)?
    var onPermissionRequired: (() -> Void)?
    var isMonitoring: Bool { controlVHotKey != nil || eventTap != nil }
    private(set) var diagnosticKeyDownCount = 0
    private(set) var diagnosticPasteShortcutCount = 0
    private(set) var diagnosticLastKeyCode: Int64 = -1

    private func writeLiveDiagnostic(_ message: String) {
        let text = "\(Date().timeIntervalSince1970)\n\(message)\n"
        DispatchQueue.global(qos: .utility).async {
            try? text.write(
                to: URL(fileURLWithPath: "/private/tmp/clipnest-live-event.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    init(picker: PickerController) {
        self.picker = picker
        picker.onPaste = { [weak self] item, previousApplication, focusedElement in
            self?.paste(item, into: previousApplication, focusedElement: focusedElement)
        }
    }

    func requestPermissionAndInstall() {
        let accessibility = AXIsProcessTrusted()
        let hotKeysReady = installCarbonHotKeys()
        let inputMonitoring = CGPreflightListenEventAccess()
        onPermissionChanged?(accessibility, inputMonitoring, hotKeysReady || eventTap != nil)
        writeLiveDiagnostic("accessibility=\(accessibility) inputMonitoring=\(inputMonitoring) eventTap=\(eventTap != nil)")
        if !hotKeysReady && accessibility && inputMonitoring { installEventTap() }
    }

    func retryIfAuthorized() {
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = CGPreflightListenEventAccess()
        let hotKeysReady = installCarbonHotKeys()
        if !hotKeysReady && accessibility && inputMonitoring, eventTap == nil {
            installEventTap()
        } else {
            onPermissionChanged?(accessibility, inputMonitoring, hotKeysReady || eventTap != nil)
        }
    }

    @discardableResult
    private func installCarbonHotKeys() -> Bool {
        if controlVHotKey != nil { return true }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        if hotKeyHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                clipNestHotKeyCallback,
                1,
                &eventType,
                pointer,
                &hotKeyHandler
            )
            guard handlerStatus == noErr else {
                writeLiveDiagnostic("carbonHandler=false status=\(handlerStatus)")
                return false
            }
        }

        let signature: OSType = 0x434C504E
        if controlVHotKey == nil {
            let controlID = EventHotKeyID(signature: signature, id: 1)
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_V),
                UInt32(controlKey),
                controlID,
                GetApplicationEventTarget(),
                0,
                &controlVHotKey
            )
            if status != noErr { writeLiveDiagnostic("controlVHotKey=false status=\(status)") }
        }
        let ready = controlVHotKey != nil
        writeLiveDiagnostic("carbonHotKey=\(ready) shortcut=control-v")
        return ready
    }

    func handleHotKey(_ event: EventRef) -> OSStatus {
        guard !synthesizingPaste else { return noErr }
        var hotKeyID = EventHotKeyID()
        var actualSize = 0
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            &actualSize,
            &hotKeyID
        )
        guard status == noErr else { return status }
        writeLiveDiagnostic("carbonHotKeyPressed id=\(hotKeyID.id)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else {
                let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
                self.onPermissionRequired?()
                return
            }
            if self.picker.isVisible {
                self.picker.cancelSelection()
            } else {
                if !self.picker.prepareForFocusedInput() {
                    self.picker.prepareFallback()
                }
                self.picker.showPrepared(showGuide: true)
            }
        }
        return noErr
    }

    private func installEventTap() {
        guard eventTap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: clipNestEventTapCallback,
            userInfo: pointer
        ) else {
            onPermissionChanged?(AXIsProcessTrusted(), CGPreflightListenEventAccess(), false)
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        let thread = Thread { [weak self] in
            guard let self else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.writeLiveDiagnostic("accessibility=true inputMonitoring=true eventTap=true dedicatedRunLoop=true")
            CFRunLoopRun()
        }
        thread.name = "ClipNest.GlobalShortcut"
        eventThread = thread
        thread.start()
        onPermissionChanged?(true, true, true)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard !synthesizingPaste else { return Unmanaged.passUnretained(event) }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if type == .keyDown {
            diagnosticKeyDownCount += 1
            diagnosticLastKeyCode = keyCode
            writeLiveDiagnostic("keyDown=\(keyCode) flags=\(flags.rawValue)")
        }
        let isPasteShortcut = keyCode == 9 &&
            flags.contains(.maskControl) && !flags.contains(.maskCommand) &&
            !flags.contains(.maskShift) && !flags.contains(.maskAlternate)

        guard isPasteShortcut else { return Unmanaged.passUnretained(event) }
        if type == .keyDown {
            diagnosticPasteShortcutCount += 1
            if !capturedV {
                capturedV = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.picker.isVisible {
                        self.picker.confirmSelection()
                    } else {
                        if !self.picker.prepareForFocusedInput() {
                            self.picker.prepareFallback()
                        }
                        self.writeLiveDiagnostic("pasteShortcut=true prepare=\(self.picker.diagnosticPreparation)")
                        self.picker.showPrepared(showGuide: true)
                    }
                }
            }
            return nil
        }
        if type == .keyUp {
            let wasCaptured = capturedV
            capturedV = false
            return wasCaptured ? nil : Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func paste(_ item: ClipItem, into previousApplication: NSRunningApplication?, focusedElement: AXUIElement?) {
        synthesizingPaste = true
        previousApplication?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if let focusedElement {
                AXUIElementSetAttributeValue(focusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }

            if !item.isImage, let focusedElement {
                let result = AXUIElementSetAttributeValue(
                    focusedElement,
                    kAXSelectedTextAttribute as CFString,
                    item.content as CFString
                )
                if result == .success {
                    self.writeLiveDiagnostic("pasteDirectAX=success kind=text target=\(previousApplication?.bundleIdentifier ?? "unknown")")
                    self.synthesizingPaste = false
                    return
                }
                self.writeLiveDiagnostic("pasteDirectAX=fallback error=\(result.rawValue)")
            }

            let pasteboard = NSPasteboard.general
            let snapshot = self.snapshotPasteboard(pasteboard)
            pasteboard.clearContents()
            if item.isImage, let image = self.picker.store.image(for: item) {
                pasteboard.writeObjects([image])
            } else {
                pasteboard.setString(item.content, forType: .string)
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            self.writeLiveDiagnostic("pasteEvent=posted kind=\(item.isImage ? "image" : "text") target=\(previousApplication?.bundleIdentifier ?? "unknown")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !snapshot.isEmpty {
                    pasteboard.clearContents()
                    pasteboard.writeObjects(snapshot)
                }
                self.synthesizingPaste = false
            }
        }
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipStore()
    private var picker: PickerController!
    private var manager: ManagerWindowController!
    private var shortcut: GlobalShortcutRuntime!
    private var statusItem: NSStatusItem!
    private var permissionMenuItem: NSMenuItem!
    private var pasteboardTimer: Timer?
    private var permissionTimer: Timer?
    private var lastPasteboardChange = NSPasteboard.general.changeCount
    private var selfTestWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        picker = PickerController(store: store)
        manager = ManagerWindowController(store: store)
        shortcut = GlobalShortcutRuntime(picker: picker)
        manager.monitoringStatus = { [weak self] in
            self?.shortcut.isMonitoring ?? false
        }
        manager.onOpenPermissionSettings = { [weak self] in
            self?.openAccessibilitySettings()
        }
        manager.onRevealApplication = {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
        shortcut.onPermissionRequired = { [weak self] in
            self?.manager.showManager()
        }
        configureStatusItem()
        shortcut.onPermissionChanged = { [weak self] accessibility, inputMonitoring, monitoring in
            DispatchQueue.main.async {
                if accessibility && monitoring {
                    self?.permissionMenuItem.title = "Ctrl+V 已启用"
                } else if !accessibility {
                    self?.permissionMenuItem.title = "需要辅助功能权限…"
                } else {
                    self?.permissionMenuItem.title = "快捷键监听未启动…"
                }
                self?.manager.updatePermissionStatus(
                    accessibility: accessibility,
                    inputMonitoring: inputMonitoring,
                    monitoring: monitoring
                )
            }
        }
        startPasteboardMonitor()
        shortcut.requestPermissionAndInstall()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.shortcut.retryIfAuthorized()
        }
        if CommandLine.arguments.contains("--self-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.runSelfTest()
            }
        }
        if CommandLine.arguments.contains("--show-manager") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.manager.showManager()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        manager.showManager()
        return true
    }

    private func runSelfTest() {
        let pasteboard = NSPasteboard.general
        let previousPasteboardItems = snapshotPasteboard(pasteboard)
        let testClipboardValue = "ClipNest 回填自检 \(UUID().uuidString.prefix(8))"
        pasteboard.clearContents()
        pasteboard.setString(testClipboardValue, forType: .string)
        lastPasteboardChange = pasteboard.changeCount

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipNest Ctrl+V 自检"
        window.center()
        let field = NSTextField(string: "测试输入框")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = "此输入框将自动测试 Ctrl+V"
        window.contentView?.addSubview(field)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                field.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                field.heightAnchor.constraint(equalToConstant: 28)
            ])
        }
        selfTestWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(field)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                let trustedBeforeTest = AXIsProcessTrusted()
                let inputMonitoringBeforeTest = CGPreflightListenEventAccess()
                let monitoringBeforeTest = self.shortcut.isMonitoring
                let source = CGEventSource(stateID: .combinedSessionState)
                let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                down?.flags = .maskControl
                up?.flags = .maskControl
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let panelOpened = self.picker.isVisible
                    self.picker.confirmSelection()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let fieldValue = field.stringValue
                        let result = [
                            "trusted=\(trustedBeforeTest)",
                            "inputMonitoring=\(inputMonitoringBeforeTest)",
                            "shortcutReady=\(monitoringBeforeTest)",
                            "panelOpened=\(panelOpened)",
                            "pasteReturnedToField=\(fieldValue.contains(testClipboardValue))",
                            "fieldValue=\(fieldValue)",
                            "keyDownCount=\(self.shortcut.diagnosticKeyDownCount)",
                            "pasteShortcutCount=\(self.shortcut.diagnosticPasteShortcutCount)",
                            "lastKeyCode=\(self.shortcut.diagnosticLastKeyCode)",
                            "prepare=\(self.picker.diagnosticPreparation)",
                            "showCount=\(self.picker.diagnosticShowCount)",
                            "hideCount=\(self.picker.diagnosticHideCount)",
                            "lastHideReason=\(self.picker.diagnosticLastHideReason)"
                        ].joined(separator: "\n") + "\n"
                        try? result.write(
                            to: URL(fileURLWithPath: "/private/tmp/clipnest-self-test.txt"),
                            atomically: true,
                            encoding: .utf8
                        )
                        self.store.removeRecentText(testClipboardValue)
                        pasteboard.clearContents()
                        if !previousPasteboardItems.isEmpty {
                            pasteboard.writeObjects(previousPasteboardItems)
                        }
                        self.lastPasteboardChange = pasteboard.changeCount
                        UserDefaults.standard.removeObject(forKey: "ClipNest.didCompleteQuickPasteGuide.v1")
                        self.picker.hide()
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipNest")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "管理内容", action: #selector(showManager), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "显示快速面板    ⌃V", action: #selector(showPicker), keyEquivalent: ""))
        menu.addItem(.separator())
        permissionMenuItem = NSMenuItem(title: "允许辅助功能…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(permissionMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 ClipNest", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func startPasteboardMonitor() {
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount != self.lastPasteboardChange else { return }
            self.lastPasteboardChange = pasteboard.changeCount
            self.store.recordPasteboard(pasteboard)
        }
    }

    @objc private func showManager() { manager.showManager() }
    @objc private func showPicker() { picker.showFromMenu() }

    @objc private func openAccessibilitySettings() {
        let privacyKey = "Privacy_Accessibility"
        let destinations = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(privacyKey)",
            "x-apple.systempreferences:com.apple.preference.security?\(privacyKey)"
        ]
        for destination in destinations {
            if let url = URL(string: destination), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
enum ClipNestApplication {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}
