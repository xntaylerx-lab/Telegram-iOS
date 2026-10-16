import UIKit

@objc(Application) class Application: UIApplication {
    // Debug touch visualiser for screen recordings, active only behind `--show-touches`.
    private let touchIndicatorOverlay: TouchIndicatorOverlay? = TouchIndicatorOverlay.isEnabled ? TouchIndicatorOverlay() : nil

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        self.touchIndicatorOverlay?.handle(event)
    }
}
