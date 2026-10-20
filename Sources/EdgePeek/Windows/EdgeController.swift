import AppKit
import Combine
import EdgePeekCore
import SwiftUI

@MainActor
final class EdgeController: NSObject {
    let store: NoteStore
    let seamState = SeamState()
    let editor = NoteEditorController()

    private var entities: [GroupEntity] = []
    private var anchor: EdgeAnchor
    private var currentScreen: NSScreen

    private var seamPanel: NSPanel!
    private var seamHost: NSHostingView<SeamView>!

    private var boardPanel: NSPanel?
    private var boardHost: NSHostingView<AnyView>?
    private var boardVisible = false
    private var boardLayout: GroupBoardLayout?

    private var previewPanel: NSPanel?
    private var previewHost: NSHostingView<AnyView>?
    private var previewVisible = false
    private var previewNoteID: UUID?

    private var cancellables = Set<AnyCancellable>()
    private var mouseTimer: Timer?
    private var dueTimer: Timer?
    private var keyMonitor: Any?
    private var dragGlow: EdgeGlowWindow?

    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var previewShowWork: DispatchWorkItem?
    private var previewHideWork: DispatchWorkItem?

    private var suppressHoverUntil = Date.distantPast
    private var ignoreHoverUntilExit = false
    private var lastOverdueIDs = Set<UUID>()
    private var shuttingDown = false
    private var demoMode = false
    private var simulatedMouse: CGPoint?
    private var activityToken: NSObjectProtocol?
    private var notesFileWatcher: NotesFileWatcher?

    private static let anchorKey = "EdgePeek.anchor.v1"

    init(store: NoteStore) {
        self.store = store

        var loadedAnchor = Self.loadAnchor()
        if let raw = ProcessInfo.processInfo.environment["EDGEPEEK_POSITION"],
           let edge = EdgeSide(rawValue: raw) {
            let screen = NSScreen.main ?? NSScreen.screens.first
            loadedAnchor = EdgeAnchor(
                edge: edge,
                fraction: 0.5,
                displayID: screen.flatMap(Self.displayID(for:))
            )
        }

        guard let screen = Self.screen(for: loadedAnchor.displayID)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        else {
            fatalError("EdgePeek needs a screen to live on.")
        }

        self.anchor = loadedAnchor
        self.currentScreen = screen
        super.init()

        // Without this an accessory app can be App Napped while the pointer is
        // already resting on the seam, which makes hover feel like it needs a
        // click to wake up.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "EdgePeek keeps the edge seam responsive"
        )

        if anchor.displayID == nil {
            anchor.displayID = Self.displayID(for: screen)
        }

        entities = GroupDataSource.entities(for: store)
        lastOverdueIDs = Set(store.overdueNotes.map(\.id))
        seamState.edge = anchor.edge
        seamState.hasDueNote = !lastOverdueIDs.isEmpty
        seamState.overdueCount = lastOverdueIDs.count

        buildSeam()
        observeStore()
        notesFileWatcher = NotesFileWatcher(fileURL: store.fileURL) { [weak self] in
            self?.store.reloadFromDiskIfChanged()
        }
        installScreenObserver()
        installKeyMonitor()
        startTimers()
        applyDebugLaunchOptions()
    }

    // MARK: - Public actions

    func createNote() {
        if editor.isOpen {
            editor.focus()
            return
        }
        closeBoard(animated: false)
        let note = store.addNote()
        openEditor(noteID: note.id, isNew: true)
    }

    func resetPosition() {
        closeBoard(animated: false)
        hidePreview(immediately: true)
        let screen = NSScreen.main ?? currentScreen
        let newAnchor = EdgeAnchor(
            edge: .left,
            fraction: 0.5,
            displayID: Self.displayID(for: screen)
        )
        anchor = newAnchor
        currentScreen = screen
        withAnimation(Theme.spring) {
            seamState.edge = newAnchor.edge
        }
        refreshSeam(reposition: true, animated: true)
        persistAnchor()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func focusEditorIfOpen() -> Bool {
        guard editor.isOpen else { return false }
        editor.focus()
        return true
    }

    func revealNotesFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    func shutdown() {
        shuttingDown = true
        mouseTimer?.invalidate()
        mouseTimer = nil
        dueTimer?.invalidate()
        dueTimer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        dragGlow?.hide(immediately: true)
        hidePreview(immediately: true)
        closeBoard(animated: false)
        editor.close(restoreFocus: false, callDismiss: false)
        store.saveNow()
        seamPanel?.orderOut(nil)
        notesFileWatcher?.stop()
        notesFileWatcher = nil
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    // MARK: - Setup

    private func buildSeam() {
        let size = SeamMetrics.panelSize(edge: anchor.edge)
        let frame = seamFrame(for: anchor, screen: currentScreen)
        let panel = PanelFactory.make(frame: frame, keyable: false)
        panel.hasShadow = false
        // The seam must survive other apps activating and full-screen spaces.
        panel.level = .screenSaver

        let view = makeSeamView()
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        seamPanel = panel
        seamHost = host
        seamState.edge = anchor.edge
        panel.orderFrontRegardless()
    }

    private func makeSeamView() -> SeamView {
        SeamView(
            state: seamState,
            onTap: { [weak self] in self?.seamTapped() },
            onDragBegan: { [weak self] in self?.beginDrag() },
            onDragMoved: { [weak self] in self?.updateDragGlow() },
            onDragEnded: { [weak self] in self?.endDrag() },
            onHoverChanged: { [weak self] inside in self?.seamHoverChanged(inside) }
        )
    }

    private func observeStore() {
        store.$notes
            .dropFirst()
            .sink { [weak self] _ in
                self?.notesChanged()
            }
            .store(in: &cancellables)
    }

    private func installScreenObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reassertSeam),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reassertSeam),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func reassertSeam() {
        guard !shuttingDown, let seamPanel else { return }
        seamPanel.orderFrontRegardless()
        if boardVisible {
            boardPanel?.orderFrontRegardless()
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53, self.editor.isOpen {
                self.editor.close()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "w",
               self.editor.isOpen {
                self.editor.close()
                return nil
            }
            return event
        }
    }

    private func startTimers() {
        let mouse = Timer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(mouseTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(mouse, forMode: .common)
        mouseTimer = mouse

        let due = Timer(
            timeInterval: 5,
            target: self,
            selector: #selector(dueTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(due, forMode: .common)
        dueTimer = due
    }

    // MARK: - Seam

    private func seamTapped() {
        if boardVisible {
            closeBoard(animated: true)
            suppressHoverUntil = Date().addingTimeInterval(0.4)
            ignoreHoverUntilExit = true
        } else {
            showBoard()
        }
    }

    private func beginDrag() {
        cancelOpen()
        cancelClose()
        hidePreview(immediately: true)
        closeBoard(animated: false)
        seamState.isHovered = true
        seamState.isDragging = true
        updateDragGlow()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func updateDragGlow() {
        let mouse = NSEvent.mouseLocation
        let screen = screen(containing: mouse) ?? screenForCurrentSeam()
        let bounds = edgeBounds(for: screen)
        let target = EdgeGeometry.anchor(for: seamPanel.frame, in: bounds)
        if dragGlow == nil {
            dragGlow = EdgeGlowWindow()
        }
        dragGlow?.present(in: bounds, edge: target.edge, fraction: target.fraction)
    }

    private func endDrag() {
        seamState.isDragging = false
        dragGlow?.hide()

        let mouse = NSEvent.mouseLocation
        let screen = screen(containing: mouse) ?? screenForCurrentSeam()
        currentScreen = screen
        let bounds = edgeBounds(for: screen)
        let newAnchor = EdgeGeometry.anchor(
            for: seamPanel.frame,
            in: bounds,
            displayID: Self.displayID(for: screen)
        )
        anchor = newAnchor

        if newAnchor.edge != seamState.edge {
            withAnimation(Theme.spring) {
                seamState.edge = newAnchor.edge
            }
        }

        let size = SeamMetrics.panelSize(edge: newAnchor.edge)
        let target = EdgeGeometry.frame(
            for: newAnchor,
            size: size,
            in: bounds,
            inset: 0
        )
        seamHost.rootView = makeSeamView()
        seamState.isSnapping = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.18, 1.0, 0.3, 1.0
            )
            seamPanel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.seamState.isSnapping = false
            }
        }

        persistAnchor()
        suppressHoverUntil = Date().addingTimeInterval(0.5)
        ignoreHoverUntilExit = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - Mouse polling

    /// Tracking-area events are immediate even if the polling timer has been
    /// throttled by the system. They make the first hover after another app has
    /// focus as reliable as the next one.
    private func seamHoverChanged(_ inside: Bool) {
        guard !shuttingDown, !demoMode, !seamState.isDragging else { return }
        seamState.isHovered = inside
        if inside {
            if boardVisible {
                cancelClose()
                return
            }
            guard !editor.isOpen,
                  !ignoreHoverUntilExit,
                  Date() >= suppressHoverUntil else { return }
            scheduleOpen(after: 0.1)
        } else {
            ignoreHoverUntilExit = false
            cancelOpen()
            if boardVisible, !isMouseInsideBoard() {
                scheduleClose(after: 0.28)
            }
        }
    }

    private func isMouseInsideBoard() -> Bool {
        guard boardVisible, let boardPanel else { return false }
        return boardPanel.frame.insetBy(dx: -6, dy: -6)
            .contains(currentMouseLocation())
    }

    @objc private func mouseTick() {
        guard !shuttingDown, !demoMode, !seamState.isDragging else { return }

        let mouse = currentMouseLocation()
        let insideSeam = seamPanel.frame.insetBy(dx: -6, dy: -6).contains(mouse)
        let insideBoard = boardVisible
            && (boardPanel?.frame.insetBy(dx: -6, dy: -6).contains(mouse) ?? false)
        let insidePreview = previewVisible
            && (previewPanel?.frame.insetBy(dx: -4, dy: -4).contains(mouse) ?? false)

        if seamState.isHovered != insideSeam {
            seamState.isHovered = insideSeam
        }
        if !insideSeam {
            ignoreHoverUntilExit = false
        }

        if boardVisible {
            if insideSeam || insideBoard || insidePreview {
                cancelClose()
            } else {
                scheduleClose(after: 0.3)
            }
        } else {
            if insideSeam,
               !ignoreHoverUntilExit,
               Date() >= suppressHoverUntil {
                scheduleOpen(after: 0.12)
            } else if !insideSeam {
                cancelOpen()
            }
        }

        if previewVisible, !insideBoard, !insidePreview, !insideSeam {
            schedulePreviewHide(after: 0.18)
        }
    }

    @objc private func dueTick() {
        updateDueState(rebuildBoard: true)
    }

    @objc private func systemDidWake() {
        updateDueState(rebuildBoard: true)
    }

    private func scheduleOpen(after delay: TimeInterval) {
        guard openWork == nil, !boardVisible, !editor.isOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openWork = nil
            guard !self.boardVisible,
                  !self.editor.isOpen,
                  self.isMouseInsideSeam(),
                  Date() >= self.suppressHoverUntil else { return }
            self.showBoard()
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelOpen() {
        openWork?.cancel()
        openWork = nil
    }

    private func scheduleClose(after delay: TimeInterval) {
        guard boardVisible, closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            guard self.boardVisible else { return }
            let mouse = self.currentMouseLocation()
            let insideSeam = self.seamPanel.frame.insetBy(dx: -6, dy: -6).contains(mouse)
            let insideBoard = self.boardPanel?.frame.insetBy(dx: -6, dy: -6).contains(mouse) ?? false
            let insidePreview = self.previewVisible
                && (self.previewPanel?.frame.insetBy(dx: -4, dy: -4).contains(mouse) ?? false)
            guard !insideSeam, !insideBoard, !insidePreview else { return }
            self.closeBoard(animated: true)
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelClose() {
        closeWork?.cancel()
        closeWork = nil
    }

    private func isMouseInsideSeam() -> Bool {
        seamPanel.frame.insetBy(dx: -6, dy: -6).contains(currentMouseLocation())
    }

    private func currentMouseLocation() -> CGPoint {
        simulatedMouse ?? NSEvent.mouseLocation
    }

    // MARK: - Board

    private func showBoard() {
        guard !boardVisible, !editor.isOpen else { return }
        cancelOpen()
        cancelClose()
        hidePreview(immediately: true)

        entities = GroupDataSource.entities(for: store)
        let layout = GroupBoardLayout.make(
            entities: entities,
            edge: anchor.edge,
            screenSize: currentScreen.visibleFrame.size
        )
        let size = layout.pageSize
        let frame = boardFrame(size: size, screen: currentScreen)
        let start = boardStartFrame(size: size, destination: frame)

        let panel = PanelFactory.make(frame: start, keyable: false)
        panel.hasShadow = false
        panel.level = .screenSaver
        let root = AnyView(
            GroupBoardView(
                layout: layout,
                edge: anchor.edge,
                actions: boardActions()
            )
        )
        let host = FirstMouseHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.alphaValue = 0
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()

        boardPanel = panel
        boardHost = host
        boardLayout = layout
        boardVisible = true
        seamState.isBoardOpen = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.18, 1.0, 0.3, 1.0
            )
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func closeBoard(animated: Bool) {
        cancelOpen()
        cancelClose()
        hidePreview(immediately: true)

        guard boardVisible || boardPanel != nil else {
            seamState.isBoardOpen = false
            return
        }

        boardVisible = false
        seamState.isBoardOpen = false
        boardLayout = nil
        guard let panel = boardPanel else { return }
        boardPanel = nil
        boardHost = nil
        panel.ignoresMouseEvents = true

        if animated, !shuttingDown {
            var target = panel.frame
            switch anchor.edge {
            case .left: target.origin.x -= 18
            case .right: target.origin.x += 18
            case .top: target.origin.y += 16
            case .bottom: target.origin.y -= 16
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        } else {
            panel.orderOut(nil)
        }
    }

    private func refreshBoard(animated: Bool) {
        guard boardVisible, let panel = boardPanel, let host = boardHost else { return }

        entities = GroupDataSource.entities(for: store)
        let layout = GroupBoardLayout.make(
            entities: entities,
            edge: anchor.edge,
            screenSize: currentScreen.visibleFrame.size
        )
        let size = layout.pageSize
        let frame = boardFrame(size: size, screen: currentScreen)
        let root = AnyView(
            GroupBoardView(
                layout: layout,
                edge: anchor.edge,
                actions: boardActions()
            )
        )

        host.rootView = root
        host.frame = NSRect(origin: .zero, size: size)
        boardLayout = layout
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func boardActions() -> BoardActions {
        BoardActions(
            openNote: { [weak self] id in
                self?.openEditor(noteID: id, isNew: false)
            },
            toggleNotePin: { [weak self] id in self?.store.togglePin(id: id) },
            setNoteDueDate: { [weak self] id, due in
                self?.store.setDueDate(id: id, dueAt: due)
                self?.updateDueState(rebuildBoard: true)
            },
            newNote: { [weak self] in self?.createNote() }
        )
    }

    private func boardFrame(size: CGSize, screen: NSScreen) -> CGRect {
        let usable = screen.visibleFrame
        let seam = seamPanel.frame
        let gap: CGFloat = 10
        var x: CGFloat
        var y: CGFloat

        switch anchor.edge {
        case .left:
            x = seam.maxX + gap
            y = seam.midY - size.height / 2
        case .right:
            x = seam.minX - gap - size.width
            y = seam.midY - size.height / 2
        case .top:
            x = seam.midX - size.width / 2
            y = seam.minY - gap - size.height
        case .bottom:
            x = seam.midX - size.width / 2
            y = seam.maxY + gap
        }

        x = EdgeGeometry.clamp(
            x,
            lower: usable.minX + 8,
            upper: usable.maxX - size.width - 8
        )
        y = EdgeGeometry.clamp(
            y,
            lower: usable.minY + 8,
            upper: usable.maxY - size.height - 8
        )
        return CGRect(x: x, y: y, width: size.width, height: size.height).integral
    }

    private func boardStartFrame(size: CGSize, destination: CGRect) -> CGRect {
        var start = destination
        switch anchor.edge {
        case .left: start.origin.x -= 18
        case .right: start.origin.x += 18
        case .top: start.origin.y += 16
        case .bottom: start.origin.y -= 16
        }
        return start
    }

    // MARK: - Preview

    private func noteHover(_ id: UUID?) {
        guard boardVisible else { return }

        if let id {
            guard previewNoteID != id else {
                previewHideWork?.cancel()
                previewHideWork = nil
                return
            }
            previewShowWork?.cancel()
            previewShowWork = nil
            previewHideWork?.cancel()
            previewHideWork = nil

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.previewShowWork = nil
                guard self.boardVisible else { return }
                self.showPreview(noteID: id)
            }
            previewShowWork = work
            let delay: TimeInterval = previewNoteID == nil ? 0.18 : 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            previewShowWork?.cancel()
            previewShowWork = nil
            if previewVisible {
                schedulePreviewHide(after: 0.2)
            }
        }
    }

    private func showPreview(noteID: UUID) {
        guard boardVisible, let note = store.note(with: noteID) else { return }

        previewShowWork?.cancel()
        previewShowWork = nil
        previewHideWork?.cancel()
        previewHideWork = nil

        let screen = screenForCurrentSeam()
        let usable = screen.visibleFrame
        let maxHeight = min(Layout.previewMaxHeight, usable.height - 28)
        let probe = NotePreviewView(note: note, edge: anchor.edge)
        let size = measuredPreviewSize(probe, note: note, maxHeight: maxHeight)

        let view = NotePreviewView(
            note: note,
            edge: anchor.edge,
            onHover: { [weak self] in self?.previewHover($0) },
            onOpen: { [weak self] in
                self?.openEditor(noteID: noteID, isNew: false)
            }
        )
        let root = AnyView(view.id(noteID))
        let mouse = currentMouseLocation()
        let frame = previewFrame(size: size, mouse: mouse, screen: screen)

        if let panel = previewPanel, let host = previewHost {
            host.rootView = root
            host.frame = NSRect(origin: .zero, size: size)
            panel.setFrame(frame, display: true)
            panel.ignoresMouseEvents = false
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            let panel = PanelFactory.make(frame: frame, keyable: false)
            let host = FirstMouseHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.alphaValue = 0
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            previewPanel = panel
            previewHost = host
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        previewVisible = true
        previewNoteID = noteID
    }

    private func measuredPreviewSize(
        _ view: NotePreviewView,
        note: StickyNote,
        maxHeight: CGFloat
    ) -> CGSize {
        let probe = NSHostingView(rootView: AnyView(view))
        probe.frame = NSRect(x: 0, y: 0, width: Layout.previewWidth, height: 300)
        probe.layoutSubtreeIfNeeded()
        let fitting = probe.fittingSize

        var height = fitting.height
        if !height.isFinite || height < 120 {
            let lineCount = min(
                NoteText.bodyLinesForDisplay(from: note.content)
                    .filter { $0.kind != .empty && $0.kind != .divider }
                    .count,
                11
            )
            height = 210 + CGFloat(lineCount) * 27
            if note.dueAt != nil { height += 8 }
            if !NoteText.tags(in: note.content).isEmpty { height += 22 }
        }

        height = min(max(height, 140), maxHeight)
        return CGSize(width: Layout.previewWidth, height: ceil(height))
    }

    private func previewFrame(size: CGSize, mouse: CGPoint, screen: NSScreen) -> CGRect {
        let usable = screen.visibleFrame
        var x = mouse.x + 22
        if x + size.width > usable.maxX - 8 {
            x = mouse.x - size.width - 22
        }
        x = EdgeGeometry.clamp(
            x,
            lower: usable.minX + 8,
            upper: usable.maxX - size.width - 8
        )
        let y = EdgeGeometry.clamp(
            mouse.y - size.height / 2,
            lower: usable.minY + 10,
            upper: usable.maxY - size.height - 10
        )
        return CGRect(x: x, y: y, width: size.width, height: size.height).integral
    }

    private func previewHover(_ hovering: Bool) {
        if hovering {
            previewHideWork?.cancel()
            previewHideWork = nil
            cancelClose()
        } else if previewVisible {
            schedulePreviewHide(after: 0.18)
        }
    }

    private func schedulePreviewHide(after delay: TimeInterval) {
        guard !demoMode, previewVisible, previewHideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewHideWork = nil
            guard self.previewVisible else { return }
            if !self.isMouseInsidePreview() {
                self.hidePreview(immediately: false)
            }
        }
        previewHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hidePreview(immediately: Bool) {
        previewShowWork?.cancel()
        previewShowWork = nil
        previewHideWork?.cancel()
        previewHideWork = nil
        guard previewVisible || previewPanel != nil else { return }

        previewVisible = false
        previewNoteID = nil
        guard let panel = previewPanel else { return }
        panel.ignoresMouseEvents = true

        if immediately || shuttingDown {
            panel.orderOut(nil)
            previewPanel = nil
            previewHost = nil
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.13
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard !self.previewVisible, self.previewPanel === panel else { return }
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                    self.previewPanel = nil
                    self.previewHost = nil
                }
            }
        }
    }

    private func isMouseInsidePreview() -> Bool {
        guard previewVisible, let previewPanel else { return false }
        return previewPanel.frame.insetBy(dx: -4, dy: -4).contains(currentMouseLocation())
    }

    // MARK: - Editor

    private func openEditor(noteID: UUID, isNew: Bool) {
        guard let note = store.note(with: noteID) else { return }
        cancelOpen()
        cancelClose()
        hidePreview(immediately: true)
        closeBoard(animated: false)
        seamState.isHovered = false
        suppressHoverUntil = Date().addingTimeInterval(0.3)

        editor.open(
            note: note,
            isNew: isNew,
            store: store,
            on: screenForCurrentSeam()
        ) { [weak self] in
            self?.suppressHoverUntil = Date().addingTimeInterval(0.3)
        }
    }

    // MARK: - Layout

    private func seamFrame(for anchor: EdgeAnchor, screen: NSScreen) -> CGRect {
        EdgeGeometry.frame(
            for: anchor,
            size: SeamMetrics.panelSize(edge: anchor.edge),
            in: edgeBounds(for: screen),
            inset: 0
        )
    }

    private func refreshSeam(reposition: Bool, animated: Bool) {
        let screen = screenForCurrentSeam()
        currentScreen = screen
        if let seamHost {
            seamHost.rootView = makeSeamView()
        }
        guard reposition, let seamPanel else { return }
        let target = seamFrame(for: anchor, screen: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.18, 1.0, 0.3, 1.0
                )
                seamPanel.animator().setFrame(target, display: true)
            }
        } else {
            seamPanel.setFrame(target, display: true)
        }
    }

    private func notesChanged() {
        hidePreview(immediately: true)
        updateDueState(rebuildBoard: false)
        if boardVisible {
            refreshBoard(animated: true)
        }
    }

    private func updateDueState(rebuildBoard: Bool) {
        let overdueIDs = Set(store.overdueNotes.map(\.id))
        let hasDue = !overdueIDs.isEmpty
        let changed = overdueIDs != lastOverdueIDs
        lastOverdueIDs = overdueIDs
        seamState.hasDueNote = hasDue
        seamState.overdueCount = overdueIDs.count

        guard changed, rebuildBoard, boardVisible else { return }
        hidePreview(immediately: true)
        refreshBoard(animated: false)
    }

    // MARK: - Screen

    @objc private func screensChanged() {
        guard !seamState.isDragging else { return }
        hidePreview(immediately: true)
        closeBoard(animated: false)

        let screen = Self.screen(for: anchor.displayID)
            ?? NSScreen.main
            ?? currentScreen
        currentScreen = screen
        var fixedAnchor = anchor
        if fixedAnchor.displayID != Self.displayID(for: screen) {
            fixedAnchor.displayID = Self.displayID(for: screen)
            anchor = fixedAnchor
            persistAnchor()
        }
        refreshSeam(reposition: true, animated: false)
    }

    /// Physical side and bottom edges; the top stays below the menu bar.
    private func edgeBounds(for screen: NSScreen) -> CGRect {
        let full = screen.frame
        let visible = screen.visibleFrame
        return CGRect(
            x: full.minX,
            y: full.minY,
            width: full.width,
            height: max(1, visible.maxY - full.minY)
        )
    }

    private func screenForCurrentSeam() -> NSScreen {
        guard let seamPanel else {
            return NSScreen.main ?? currentScreen
        }
        let center = CGPoint(x: seamPanel.frame.midX, y: seamPanel.frame.midY)
        return screen(containing: center) ?? NSScreen.main ?? currentScreen
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.min { lhs, rhs in
                squaredDistance(lhs.frame.center, point)
                    < squaredDistance(rhs.frame.center, point)
            }
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    // MARK: - Persistence

    private func persistAnchor() {
        do {
            let data = try JSONEncoder().encode(anchor)
            UserDefaults.standard.set(data, forKey: Self.anchorKey)
        } catch {
            NSLog("EdgePeek: could not persist anchor: \(error.localizedDescription)")
        }
    }

    private static func loadAnchor() -> EdgeAnchor {
        guard let data = UserDefaults.standard.data(forKey: anchorKey),
              let anchor = try? JSONDecoder().decode(EdgeAnchor.self, from: data)
        else {
            return EdgeAnchor(edge: .left, fraction: 0.5)
        }
        return anchor
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private static func screen(for displayID: UInt32?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { Self.displayID(for: $0) == displayID }
    }

    // MARK: - Development launch options

    private func applyDebugLaunchOptions() {
        let environment = ProcessInfo.processInfo.environment

        if environment["EDGEPEEK_DEMO"] == "1"
            || environment["EDGEPEEK_HOLD"] == "1" {
            demoMode = true
        }

        if environment["EDGEPEEK_DUE_DEMO"] == "1" {
            if let first = store.sortedNotes.first {
                store.setDueDate(id: first.id, dueAt: Date().addingTimeInterval(-60))
                updateDueState(rebuildBoard: true)
            }
        }

        if environment["EDGEPEEK_SIMULATE_HOVER"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                self.simulatedMouse = CGPoint(
                    x: self.seamPanel.frame.midX,
                    y: self.seamPanel.frame.midY
                )
                self.mouseTick()
            }
        }

        if environment["EDGEPEEK_DEMO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showBoard()
            }
        }

        if environment["EDGEPEEK_EDITOR"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.closeBoard(animated: false)
                let notes = self.store.sortedNotes
                let index = max(
                    0,
                    Int(environment["EDGEPEEK_NOTE_INDEX"] ?? "0") ?? 0
                )
                guard notes.indices.contains(index) else { return }
                self.openEditor(noteID: notes[index].id, isNew: false)
            }
        }
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
