import Cocoa
import ServiceManagement

// MARK: - Grille et mouvement

let pillH: CGFloat = 48, side: CGFloat = 36, inset: CGFloat = 6, gap: CGFloat = 2, sepAir: CGFloat = 4
let padX: CGFloat = 40, padTop: CGFloat = 10, padBottom: CGFloat = 40
let maxW = pillWidth(8)
let curve = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
let scale = NSScreen.main?.backingScaleFactor ?? 2

func pillWidth(_ n: Int) -> CGFloat { 2 * inset + CGFloat(n + 1) * side + CGFloat(max(n - 1, 0)) * gap + 2 * sepAir + 1 }
func snap(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
func arg(_ name: String) -> String? {
    CommandLine.arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
}

/// La même courbe (0.22, 1, 0.36, 1), évaluée à la main pour les animations pilotées image par image.
func bezier(_ x: Double) -> Double {
    func b(_ t: Double, _ p1: Double, _ p2: Double) -> Double { 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t }
    var lo = 0.0, hi = 1.0
    for _ in 0..<30 { let m = (lo + hi) / 2; if b(m, 0.22, 0.36) < x { lo = m } else { hi = m } }
    return b((lo + hi) / 2, 1, 1)
}

func spring(_ l: CALayer, _ key: String, to v: CGFloat, from: CGFloat? = nil, delay: CFTimeInterval = 0) {
    let a = CASpringAnimation(keyPath: key)
    a.damping = 22; a.stiffness = 380
    a.fromValue = from ?? (l.presentation()?.value(forKeyPath: key) ?? l.value(forKeyPath: key))
    a.toValue = v
    a.duration = a.settlingDuration
    if delay > 0 { a.beginTime = CACurrentMediaTime() + delay; a.fillMode = .backwards }
    l.setValue(v, forKeyPath: key)
    l.add(a, forKey: key)
}

func ease(_ l: CALayer, _ key: String, to v: CGFloat, _ d: CFTimeInterval, from: CGFloat? = nil, delay: CFTimeInterval = 0) {
    let a = CABasicAnimation(keyPath: key)
    a.fromValue = from ?? (l.presentation()?.value(forKeyPath: key) ?? l.value(forKeyPath: key))
    a.toValue = v; a.duration = d; a.timingFunction = curve
    if delay > 0 { a.beginTime = CACurrentMediaTime() + delay; a.fillMode = .backwards }
    l.setValue(v, forKeyPath: key)
    l.add(a, forKey: key)
}

func fade(_ views: [NSView], _ alpha: CGFloat, _ d: Double, done: (() -> Void)? = nil) {
    NSAnimationContext.runAnimationGroup({ c in
        c.duration = d; c.timingFunction = curve
        views.forEach { $0.animator().alphaValue = alpha }
    }, completionHandler: done)
}

/// Anime une valeur image par image (largeur de la pilule) avec la courbe commune.
final class Tween: NSObject {
    let start = CACurrentMediaTime(), duration: Double, update: (CGFloat) -> Void
    var link: CADisplayLink?
    init(_ view: NSView, _ duration: Double, _ update: @escaping (CGFloat) -> Void) {
        self.duration = duration; self.update = update
        super.init()
        link = view.displayLink(target: self, selector: #selector(step))
        link?.add(to: .main, forMode: .common)
    }
    @objc func step() {
        let p = min((CACurrentMediaTime() - start) / duration, 1)
        update(CGFloat(bezier(p)))
        if p >= 1 { stop() }
    }
    func stop() { link?.invalidate(); link = nil }
}

/// Dessine dans une case, puis recentre au pixel près d'après la zone réellement encrée.
func centeredImage(_ draw: (NSRect) -> Void) -> CGImage {
    let px = Int(side * scale)
    func context() -> CGContext {
        CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    let ctx = context()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.scaleBy(x: scale, y: scale)
    draw(NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var (x0, y0, x1, y1) = (px, px, -1, -1)
    for y in 0..<px { for x in 0..<px where data[(y * px + x) * 4 + 3] > 8 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    let image = ctx.makeImage()!
    guard x1 >= 0, let crop = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)) else { return image }
    let out = context()
    out.draw(crop, in: CGRect(x: (px - crop.width) / 2, y: (px - crop.height) / 2, width: crop.width, height: crop.height))
    return out.makeImage()!
}

func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: size, weight: weight))!
}

// MARK: - Case commune (emojis et crayon)

final class Cell: NSView {
    let circle = CALayer(), content = CALayer()
    var onClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var enabled: () -> Bool = { true }
    var pressable = false, hovered = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        circle.frame = bounds
        circle.cornerRadius = side / 2
        circle.opacity = 0
        content.frame = bounds
        content.contentsScale = scale
        layer!.addSublayer(circle)
        layer!.addSublayer(content)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            circle.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        }
    }
    func hover(_ on: Bool) {
        guard on != hovered else { return }
        hovered = on
        ease(circle, "opacity", to: on ? 1 : 0, 0.14)
        onHover(on)
    }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { if enabled() { hover(true) } }
    override func mouseExited(with e: NSEvent) { hover(false) }
    override func mouseDown(with e: NSEvent) {
        if enabled() && pressable { spring(content, "transform.scale", to: 0.88) }
    }
    override func mouseUp(with e: NSEvent) {
        guard enabled() else { return }
        let inside = bounds.contains(convert(e.locationInWindow, from: nil))
        if pressable { spring(content, "transform.scale", to: inside || !hovered ? 1 : 1.12) }
        if inside { onClick() }
    }
}

// MARK: - Application

final class Panel: NSPanel { override var canBecomeKey: Bool { true } }
final class Root: NSView {
    var onAppearance: () -> Void = {}
    override func viewDidChangeEffectiveAppearance() { onAppearance() }
}

enum Mode { case normal, edit, copied }

final class App: NSObject, NSApplicationDelegate {
    var emojis = App.loadEmojis()
    var item: NSStatusItem!
    let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let root = Root(), shade = NSView(), pill = NSView(), clip = Root()
    let shadeMask = CAShapeLayer(), sep = CALayer(), check = CALayer()
    let pencil = Cell(), pencilIcon = NSImageView(), okIcon = NSImageView(), field = NSTextField(string: "")
    var bg: NSView!
    var cells: [Cell] = []
    var mode = Mode.normal, width: CGFloat = 0, session = 0
    var tween: Tween?
    var monitors: [Any] = []
    var previousApp: NSRunningApplication?
    let frozen = arg("state") != nil

    /// Les plus utilisés d'abord. L'ancienne liste par défaut, jamais personnalisée, passe à la nouvelle.
    static func loadEmojis() -> [String] {
        let stored = UserDefaults.standard.stringArray(forKey: "emojis")
        if let stored, stored != ["👍", "🙏", "😂", "🔥", "✅", "❤️"], !stored.isEmpty { return stored }
        return ["😂", "❤️", "👍", "🙏", "😭", "🥰", "🔥", "✅"]
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        installEditMenu()
        if let a = arg("appearance") { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true           // récupère l'icône si elle a été retirée de la barre avec ⌘-glisser
        let icon = symbol("face.smiling", 15, .regular)
        icon.isTemplate = true
        item.button?.image = icon
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        build()
        let defaults = UserDefaults.standard
        let firstLaunch = !defaults.bool(forKey: "launchedOnce")
        if !frozen {
            defaults.set(true, forKey: "launchedOnce")
            syncLoginItem(firstLaunch: firstLaunch)
        }
        if CommandLine.arguments.contains("--debug") { print("ouverture de session :", SMAppService.mainApp.status.rawValue); fflush(stdout) }
        if CommandLine.arguments.contains("--show") || frozen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.show(); self.freeze() }
        }
    }

    /// Relancer l'app (Spotlight, Finder) ouvre la bulle : utile si l'icône est cachée par l'encoche.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if monitors.isEmpty { show() }
        return false
    }

    /// Sans menu Édition, ni ⌘V ni Ctrl+⌘+Espace n'atteignent le champ (macOS y ajoute lui-même le sélecteur d'emojis).
    func installEditMenu() {
        let main = NSMenu(), holder = NSMenuItem(), edit = NSMenu(title: "Édition")
        for (title, action, key) in [("Annuler", Selector(("undo:")), "z"), ("Couper", #selector(NSText.cut(_:)), "x"),
                                     ("Copier", #selector(NSText.copy(_:)), "c"), ("Coller", #selector(NSText.paste(_:)), "v"),
                                     ("Tout sélectionner", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        holder.submenu = edit
        main.addItem(holder)
        NSApp.mainMenu = main
    }

    /// Ouverture de session : activée une fois au premier lancement, ensuite le choix du menu fait foi.
    func syncLoginItem(firstLaunch: Bool) {
        let defaults = UserDefaults.standard
        if firstLaunch { defaults.set(true, forKey: "loginItem") }
        let status = SMAppService.mainApp.status
        if defaults.bool(forKey: "loginItem"), status == .notRegistered || status == .notFound {
            do { try SMAppService.mainApp.register() } catch { print("ouverture de session :", error); fflush(stdout) }
        }
    }

    @objc func toggleLoginItem() {
        let on = SMAppService.mainApp.status == .enabled
        if on { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
        UserDefaults.standard.set(!on, forKey: "loginItem")
    }

    func build() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false        // ombre dessinée par nous : elle suit la pilule sans clignoter
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]   // visible aussi par-dessus le plein écran
        panel.contentView = root
        root.wantsLayer = true
        clip.onAppearance = { [unowned self] in resolveColors() }

        shade.wantsLayer = true
        shade.layer!.shadowOpacity = 1
        shade.layer!.shadowRadius = 14
        shade.layer!.shadowOffset = CGSize(width: 0, height: -5)
        shadeMask.fillRule = .evenOdd   // pas d'ombre sous le verre, seulement autour
        shade.layer!.mask = shadeMask
        root.addSubview(shade)

        pill.wantsLayer = true
        root.addSubview(pill)
        clip.wantsLayer = true
        clip.layer!.cornerRadius = pillH / 2
        clip.layer!.cornerCurve = .continuous
        clip.layer!.masksToBounds = true
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = pillH / 2
            glass.contentView = clip
            bg = glass
            pill.addSubview(glass)
        } else {
            let v = NSVisualEffectView()
            v.material = .popover
            v.blendingMode = .behindWindow
            v.state = .active
            v.wantsLayer = true
            v.layer!.cornerRadius = pillH / 2
            v.layer!.cornerCurve = .continuous
            v.layer!.masksToBounds = true
            clip.layer!.borderWidth = 0.5
            bg = v
            pill.addSubview(v)
            pill.addSubview(clip)
        }

        clip.layer!.addSublayer(sep)
        check.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let mask = CALayer()
        mask.frame = check.bounds
        mask.contentsScale = scale
        mask.contents = centeredImage { r in
            let img = symbol("checkmark", 17, .semibold)
            img.draw(in: NSRect(x: (r.width - img.size.width) / 2, y: (r.height - img.size.height) / 2,
                                width: img.size.width, height: img.size.height))
        }
        check.mask = mask
        clip.layer!.addSublayer(check)

        for (v, name) in [(pencilIcon, "pencil"), (okIcon, "checkmark")] {
            v.image = symbol(name, 13, .medium)
            v.imageScaling = .scaleNone
            v.frame = pencil.bounds
            v.contentTintColor = .secondaryLabelColor
            pencil.addSubview(v)
        }
        pencil.onHover = { [unowned self] on in
            for v in [pencilIcon, okIcon] { v.contentTintColor = on ? .labelColor : .secondaryLabelColor }
        }
        pencil.enabled = { [unowned self] in mode != .copied }
        pencil.onClick = { [unowned self] in mode == .edit ? endEdit(save: true) : edit() }
        clip.addSubview(pencil)

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .systemFont(ofSize: 22)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.target = self
        field.action = #selector(commit)
        clip.addSubview(field)
        resolveColors()
    }

    func resolveColors() {
        // Le verre adapte l'apparence de son contenu à l'arrière-plan : on résout sur celle du contenu.
        clip.effectiveAppearance.performAsCurrentDrawingAppearance {
            sep.backgroundColor = NSColor.separatorColor.cgColor
            check.backgroundColor = NSColor.labelColor.cgColor
            clip.layer!.borderColor = NSColor.separatorColor.cgColor
            shade.layer!.shadowColor = NSColor.shadowColor.withAlphaComponent(0.22).cgColor
        }
    }

    // MARK: Mise en page (appelée à chaque image pendant les transitions)

    func place(_ w: CGFloat) {
        width = snap(w)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.frame = NSRect(x: snap((root.bounds.width - width) / 2), y: padBottom, width: width, height: pillH)
        bg.frame = pill.bounds
        clip.frame = pill.bounds
        let ox = snap((width - pillWidth(emojis.count)) / 2)   // les emojis restent fixes à l'écran
        for (i, c) in cells.enumerated() { c.setFrameOrigin(NSPoint(x: ox + inset + CGFloat(i) * (side + gap), y: inset)) }
        pencil.setFrameOrigin(NSPoint(x: width - inset - side, y: inset))
        sep.frame = CGRect(x: width - inset - side - sepAir - 1, y: (pillH - 16) / 2, width: 1, height: 16)
        let fh = ceil(field.fittingSize.height)
        field.frame = NSRect(x: inset, y: snap((pillH - fh) / 2), width: max(width - 2 * inset - side - 2 * sepAir - 1, 0), height: fh)
        check.position = CGPoint(x: width / 2, y: pillH / 2)
        let path = CGPath(roundedRect: pill.frame, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)
        shade.frame = root.bounds
        shade.layer!.shadowPath = path
        let hole = CGMutablePath()
        hole.addRect(root.bounds)
        hole.addPath(path)
        shadeMask.path = hole
        CATransaction.commit()
    }

    func animateWidth(to target: CGFloat, _ d: Double = 0.32) {
        tween?.stop()
        let from = width
        tween = Tween(root, d) { [unowned self] p in place(from + (target - from) * p) }
    }

    /// Transformation d'échelle autour d'un point de la vue racine.
    func scaled(_ s: CGFloat, about p: CGPoint) -> CATransform3D {
        let l = root.layer!
        let a = CGPoint(x: l.anchorPoint.x * l.bounds.width, y: l.anchorPoint.y * l.bounds.height)
        let t = CATransform3DScale(CATransform3DMakeTranslation(p.x - a.x, p.y - a.y, 0), s, s, 1)
        return CATransform3DTranslate(t, a.x - p.x, a.y - p.y, 0)
    }

    func rebuildCells() {
        cells.forEach { $0.removeFromSuperview() }
        cells = emojis.map { e in
            let c = Cell()
            let text = NSAttributedString(string: e, attributes: [.font: NSFont.systemFont(ofSize: 22)])
            c.content.contents = centeredImage { r in
                let s = text.size()
                text.draw(at: NSPoint(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2))
            }
            c.pressable = true
            c.enabled = { [unowned self] in mode == .normal }
            c.onHover = { [unowned c] on in spring(c.content, "transform.scale", to: on ? 1.12 : 1) }
            c.onClick = { [unowned self, unowned c] in copy(c) }
            c.viewDidChangeEffectiveAppearance()
            clip.addSubview(c, positioned: .below, relativeTo: pencil)
            return c
        }
    }

    // MARK: Ouverture / fermeture

    @objc func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if !monitors.isEmpty { close() }
            let menu = NSMenu()
            let login = menu.addItem(withTitle: "Ouvrir à l'ouverture de session", action: #selector(toggleLoginItem), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else if monitors.isEmpty { show() } else { close() }   // monitors vide : fermée ou en train de s'effacer
    }

    /// Point d'accroche sous l'icône. Barre de menu masquée (plein écran) ou icône cachée : le cadre est vide,
    /// on s'accroche alors en haut de l'écran où se trouve la souris, sous la zone de l'encoche.
    func anchor() -> (screen: NSScreen, x: CGFloat, y: CGFloat)? {
        if let w = item.button?.window, let s = w.screen, w.frame.width > 0, w.frame.height > 0,
           s.frame.contains(CGPoint(x: w.frame.midX, y: w.frame.midY)) {
            return (s, w.frame.midX, w.frame.minY)
        }
        let mouse = NSEvent.mouseLocation
        guard let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return nil }
        return (s, s.frame.midX, s.frame.maxY - max(s.safeAreaInsets.top, s.frame.maxY - s.visibleFrame.maxY))
    }

    func show() {
        guard let (screen, ax, ay) = anchor() else { return }
        session += 1
        let cx = min(max(ax, screen.frame.minX + 8 + maxW / 2), screen.frame.maxX - 8 - maxW / 2)
        let size = NSSize(width: maxW + 2 * padX, height: padBottom + pillH + padTop)
        panel.setFrame(NSRect(x: (cx - size.width / 2).rounded(), y: ay - 6 - pillH - padBottom,
                              width: size.width, height: size.height), display: false)
        root.layer!.removeAllAnimations()
        reset()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.26; c.timingFunction = curve; panel.animator().alphaValue = 1 }
        let zoom = CABasicAnimation(keyPath: "transform")
        zoom.fromValue = scaled(0.94, about: CGPoint(x: pill.frame.midX, y: pill.frame.maxY))
        zoom.toValue = CATransform3DIdentity
        zoom.duration = 0.26
        zoom.timingFunction = curve
        root.layer!.add(zoom, forKey: "zoom")
        for (i, c) in cells.enumerated() {
            ease(c.content, "opacity", to: 1, 0.2, from: 0, delay: Double(i) * 0.02)
            spring(c.content, "transform.scale", to: 1, from: 0.85, delay: Double(i) * 0.02)
        }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [unowned self] _ in
                if mode == .normal && !frozen { close() }
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [unowned self] e in
                guard e.window == panel, mode == .normal, !pill.frame.contains(root.convert(e.locationInWindow, from: nil)) else { return e }
                close()
                return nil
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] e in
                if e.keyCode == 53 {
                    if mode == .edit { endEdit(save: false) } else { close() }
                    return nil
                }
                // 1 à 8 copient directement, y compris sur un clavier AZERTY (touches physiques).
                if mode == .normal, e.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                   let i = [18, 19, 20, 21, 23, 22, 26, 28].firstIndex(of: Int(e.keyCode)), i < cells.count {
                    copy(cells[i])
                    return nil
                }
                return e
            } as Any,
        ]
    }

    func reset() {
        mode = .normal
        tween?.stop()
        rebuildCells()
        pencil.hover(false)
        pencil.alphaValue = 1
        pencilIcon.alphaValue = 1
        okIcon.alphaValue = 0
        field.isHidden = true
        field.alphaValue = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sep.opacity = 1
        check.opacity = 0
        CATransaction.commit()
        place(pillWidth(emojis.count))
    }

    func dismiss(_ duration: Double, shrink: Bool = false) {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        let current = session
        if shrink {
            let a = CABasicAnimation(keyPath: "transform")
            a.toValue = scaled(0.92, about: CGPoint(x: pill.frame.midX, y: pill.frame.midY))
            a.duration = duration
            a.timingFunction = curve
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            root.layer!.add(a, forKey: "zoom")
        }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = duration; c.timingFunction = curve; panel.animator().alphaValue = 0
        }, completionHandler: { [unowned self] in
            if session == current { panel.orderOut(nil); root.layer!.removeAllAnimations() }
        })
    }

    func close() {
        if mode == .edit { panel.makeFirstResponder(nil); restoreFocus() }
        mode = .normal
        dismiss(0.12)
    }

    // MARK: Copie

    func copy(_ cell: Cell) {
        mode = .copied
        if !frozen {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(emojis[cells.firstIndex(of: cell)!], forType: .string)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        cells.forEach { $0.hover(false) }
        pencil.hover(false)
        fade(cells + [pencil], 0, 0.12)
        ease(sep, "opacity", to: 0, 0.12)
        ease(check, "opacity", to: 1, 0.12)
        spring(check, "transform.scale", to: 1, from: 0.5)
        animateWidth(to: pillH)
        let current = session
        if !frozen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32 + 0.6) { [unowned self] in
                if session == current && mode == .copied { dismiss(0.18, shrink: true) }
            }
        }
    }

    // MARK: Mode crayon

    func edit() {
        mode = .edit
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == .current ? nil : front
        cells.forEach { $0.hover(false) }
        fade(cells, 0, 0.12)
        field.stringValue = emojis.joined()
        field.isHidden = false
        fade([field], 1, 0.2)
        fade([pencilIcon], 0, 0.2)
        fade([okIcon], 1, 0.2)
        animateWidth(to: maxW)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @objc func commit() { endEdit(save: true) }

    func endEdit(save: Bool) {
        guard mode == .edit else { return }
        if save {
            let kept = App.parseEmojis(field.stringValue)
            if !kept.isEmpty && Array(kept) != emojis {
                emojis = Array(kept)
                UserDefaults.standard.set(emojis, forKey: "emojis")
                rebuildCells()
                cells.forEach { $0.alphaValue = 0 }
            }
        }
        mode = .normal
        panel.makeFirstResponder(nil)
        fade([field], 0, 0.12) { [unowned self] in if mode != .edit { field.isHidden = true } }
        fade(cells, 1, 0.2)
        fade([pencilIcon], 1, 0.2)
        fade([okIcon], 0, 0.2)
        animateWidth(to: pillWidth(emojis.count))
        restoreFocus()
    }

    /// Découpe par Character, sans repasser par une String : deux drapeaux voisins ne peuvent pas fusionner.
    static func parseEmojis(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.compactMap { c -> String? in
            let s = c.unicodeScalars, first = s.first!
            guard first.value > 0x7F else { return nil }   // chiffres, # et * (y compris en keycap)
            let colored = s.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
            guard colored || (first.properties.isEmoji && first.value > 0x2000) else { return nil }
            return colored ? String(c) : String(c) + "\u{FE0F}"   // ❤ nu s'afficherait en noir et blanc
        }.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    func restoreFocus() {
        previousApp?.activate()
        previousApp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [unowned self] in
            if panel.isVisible && mode == .normal { panel.makeKey() }   // Échap reste actif
        }
    }

    // MARK: Vérification (--state, --debug-layout)

    func freeze() {
        switch arg("state") {
        case "hover": cells[min(1, cells.count - 1)].hover(true)
        case "copied": copy(cells[0])
        case "edit": edit()
        default: break
        }
        if CommandLine.arguments.contains("--selftest") {
            print(App.parseEmojis("a1#*👍🏽🇫🇷🇩🇪👨‍👩‍👧❤👍🏽1️⃣🙂🙂😀😁😂🤣😃"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                let editor = panel.firstResponder as? NSTextView
                print("répondeur :", panel.firstResponder.map { String(describing: type(of: $0)) } ?? "aucun", "· clé :", panel.isKeyWindow)
                editor?.setSelectedRange(NSRange(location: 0, length: 0))
                NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                 windowNumber: panel.windowNumber, context: nil, characters: "a",
                                                 charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!)
                print("⌘A sélectionne :", editor?.selectedRange().length ?? -1)
                print("menu Édition :", NSApp.mainMenu?.items.first?.submenu?.items.map(\.title) ?? [])
                fflush(stdout)
            }
            fflush(stdout)
        }
        if CommandLine.arguments.contains("--debug-layout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.report() }
        }
    }

    func report() {
        var issues: [String] = []
        func line(_ name: String, _ f: CGRect) {
            let d = f.midY - pillH / 2
            print(String(format: "%-8@ x=%6.1f y=%5.1f w=%5.1f h=%5.1f  centreY=%5.2f", name as NSString, f.minX, f.minY, f.width, f.height, f.midY))
            if abs(d) > 0.5 { issues.append("\(name) : centre vertical décalé de \(d) pt") }
        }
        print("pilule  w=\(width) h=\(pillH)  centreY=\(pillH / 2)  mode=\(mode)")
        for (i, c) in cells.enumerated() where c.alphaValue > 0 { line("emoji\(i)", c.frame) }
        if pencil.alphaValue > 0 { line("crayon", pencil.frame); line("sép.", sep.frame) }
        if !field.isHidden { line("champ", field.frame) }
        if check.opacity > 0 { line("coche", check.frame) }
        if mode == .normal, let first = cells.first {
            let l = first.frame.minX, r = width - pencil.frame.maxX, t = pillH - pencil.frame.maxY, b = pencil.frame.minY
            print("marges  gauche=\(l) droite=\(r) haut=\(t) bas=\(b)")
            if abs(l - r) > 0.5 || abs(t - l) > 0.5 || abs(b - l) > 0.5 { issues.append("marges inégales") }
        }
        let f = panel.convertToScreen(root.convert(pill.frame, to: nil)).insetBy(dx: -30, dy: -30)
        let top = (NSScreen.screens.first?.frame.height ?? 0) - f.maxY
        print(String(format: "capture -R%.0f,%.0f,%.0f,%.0f", f.minX, top, f.width, f.height))
        print(issues.isEmpty ? "OK : aucun écart > 0,5 pt" : issues.map { "⚠️ " + $0 }.joined(separator: "\n"))
        fflush(stdout)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
