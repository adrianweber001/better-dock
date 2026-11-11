import AppKit
import QuartzCore

/// Kurze Animation an der Stelle, an der eine App in einen Ordner gelegt wurde:
/// Ein Ordner-Feld springt auf, die App schrumpft hinein, dann blendet alles aus.
enum MergeAnimation {
    private static var window: NSWindow?

    static func play(at mouse: NSPoint, source: String, target: String) {
        let side: CGFloat = 150
        let window = NSWindow(contentRect: NSRect(x: mouse.x - side / 2, y: mouse.y - side / 2, width: side, height: side),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        content.wantsLayer = true
        guard let root = content.layer else { return }
        let center = CGPoint(x: side / 2, y: side / 2)

        let plate = CALayer()
        plate.bounds = CGRect(x: 0, y: 0, width: 96, height: 96)
        plate.position = center
        plate.cornerRadius = 22
        plate.backgroundColor = NSColor(white: 0.7, alpha: 0.8).cgColor
        plate.borderColor = NSColor(white: 1, alpha: 0.9).cgColor
        plate.borderWidth = 2
        plate.shadowOpacity = 0.3
        plate.shadowRadius = 8
        root.addSublayer(plate)

        func iconLayer(_ path: String, x: CGFloat) -> CALayer {
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
            layer.position = CGPoint(x: x, y: center.y)
            layer.contents = NSWorkspace.shared.icon(forFile: path).cgImage(forProposedRect: nil, context: nil, hints: nil)
            layer.contentsGravity = .resizeAspect
            root.addSublayer(layer)
            return layer
        }
        let targetIcon = iconLayer(target, x: center.x - 21)
        let sourceIcon = iconLayer(source, x: center.x + 21)

        // Ordner-Feld springt auf.
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.4
        pop.toValue = 1
        pop.damping = 11
        pop.duration = pop.settlingDuration
        plate.add(pop, forKey: "pop")
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = 0.18
        plate.add(fadeIn, forKey: "fade")
        targetIcon.add(fadeIn, forKey: "fade")

        // Die gezogene App schrumpft von der Mitte an ihren Platz im Ordner.
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 2.2
        shrink.toValue = 1
        let slide = CABasicAnimation(keyPath: "position")
        slide.fromValue = NSValue(point: center)
        slide.toValue = NSValue(point: sourceIcon.position)
        let move = CAAnimationGroup()
        move.animations = [shrink, slide]
        move.duration = 0.38
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        sourceIcon.add(move, forKey: "move")

        window.contentView = content
        window.orderFrontRegardless()
        self.window?.orderOut(nil)
        self.window = window

        // Bleibt stehen, bis das Dock neu da ist, und blendet dann aus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
                if self.window === window { self.window = nil }
            })
        }
    }
}
