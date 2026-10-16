import UIKit

/// Debug-only visualiser that draws a translucent disc under every touch, so that screen
/// recordings of the simulator show taps the way Telegram's own feature demos do.
///
/// It is created only when the app is launched with `--show-touches`
/// (`xcrun simctl launch <udid> ph.telegra.Telegraph --show-touches`); without the argument
/// nothing is allocated. Touches are observed in `Application.sendEvent(_:)`, which sees the
/// touches of every window, including the system keyboard window. The discs live in a
/// dedicated pass-through window above the app's own windows, so hit-testing is unaffected.
final class TouchIndicatorOverlay {
    static let isEnabled = CommandLine.arguments.contains("--show-touches")

    private static let diameter: CGFloat = 26.0
    private static let fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
    private static let ringColor = UIColor.white.withAlphaComponent(0.65).cgColor
    private static let ringWidth: CGFloat = 1.5

    /// UIKit clamps window levels to 1e7, so this is the highest level an app window can get.
    /// The system keyboard window sits at 1e7 + 1, above anything the app can create; touches
    /// in such windows are drawn into the touched window itself (see `hostWindow(for:)`).
    private static let windowLevel = UIWindow.Level(rawValue: 10_000_000.0)

    private var window: UIWindow?
    private var layers: [ObjectIdentifier: CALayer] = [:]

    func handle(_ event: UIEvent) {
        guard event.type == .touches, let touches = event.allTouches, !touches.isEmpty else {
            return
        }
        for touch in touches {
            guard let touchWindow = touch.window, let host = self.hostWindow(for: touchWindow) else {
                continue
            }
            let key = ObjectIdentifier(touch)
            let screenPoint = touchWindow.convert(touch.location(in: nil), to: nil)
            let point = host.convert(screenPoint, from: nil)

            switch touch.phase {
            case .began:
                self.layers[key]?.removeFromSuperlayer()
                let layer = self.makeDiscLayer(at: point)
                host.layer.addSublayer(layer)
                self.layers[key] = layer
                self.animateAppearance(of: layer)
            case .moved, .stationary:
                guard let layer = self.layers[key] else {
                    continue
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.position = point
                CATransaction.commit()
            case .ended, .cancelled:
                guard let layer = self.layers.removeValue(forKey: key) else {
                    continue
                }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.position = point
                CATransaction.commit()
                self.animateDisappearance(of: layer)
            default:
                continue
            }
        }
    }

    /// The window whose layer tree receives the disc. Normally the overlay window; for a touch
    /// in a window that is at or above the overlay's level (the system keyboard window, which
    /// UIKit keeps above every app window) the touched window itself, so that the disc is not
    /// hidden under it.
    private func hostWindow(for touchWindow: UIWindow) -> UIWindow? {
        if touchWindow.windowLevel >= TouchIndicatorOverlay.windowLevel {
            return touchWindow
        }
        return self.overlayWindow(for: touchWindow)
    }

    private func overlayWindow(for touchWindow: UIWindow) -> UIWindow? {
        if let window = self.window {
            return window
        }
        let window: UIWindow
        if let windowScene = touchWindow.windowScene {
            window = UIWindow(windowScene: windowScene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = TouchIndicatorOverlay.windowLevel
        window.isUserInteractionEnabled = false
        window.backgroundColor = .clear
        window.rootViewController = TouchIndicatorRootViewController()
        window.isHidden = false
        self.window = window
        return window
    }

    private func makeDiscLayer(at point: CGPoint) -> CALayer {
        let layer = CALayer()
        let diameter = TouchIndicatorOverlay.diameter
        layer.bounds = CGRect(x: 0.0, y: 0.0, width: diameter, height: diameter)
        layer.position = point
        layer.cornerRadius = diameter / 2.0
        layer.backgroundColor = TouchIndicatorOverlay.fillColor
        layer.borderColor = TouchIndicatorOverlay.ringColor
        layer.borderWidth = TouchIndicatorOverlay.ringWidth
        layer.zPosition = 1.0
        return layer
    }

    private func animateAppearance(of layer: CALayer) {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue = 1.0
        scale.duration = 0.12
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(scale, forKey: "appear")
    }

    private func animateDisappearance(of layer: CALayer) {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.25
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 0.2
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.removeFromSuperlayer()
        }
        layer.add(group, forKey: "disappear")
        CATransaction.commit()
    }
}

/// Root controller of the overlay window. A full-screen window at a higher level than the
/// app window takes over the status bar appearance and the supported orientations, so this
/// mirrors whatever the key window's root controller currently wants.
private final class TouchIndicatorRootViewController: UIViewController {
    private var source: UIViewController? {
        guard let windowScene = self.view.window?.windowScene else {
            return nil
        }
        guard let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }), keyWindow !== self.view.window else {
            return nil
        }
        return keyWindow.rootViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .clear
        self.view.isUserInteractionEnabled = false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard var controller = self.source else {
            return .default
        }
        while let child = controller.childForStatusBarStyle {
            controller = child
        }
        return controller.preferredStatusBarStyle
    }

    override var prefersStatusBarHidden: Bool {
        guard var controller = self.source else {
            return false
        }
        while let child = controller.childForStatusBarHidden {
            controller = child
        }
        return controller.prefersStatusBarHidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return self.source?.prefersHomeIndicatorAutoHidden ?? false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return self.source?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
}
