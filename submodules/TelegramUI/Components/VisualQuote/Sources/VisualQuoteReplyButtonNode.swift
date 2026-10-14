import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import GlassControls

/// The "Reply" control that appears next to a selection in the gallery. It reuses
/// the glass control group the gallery footer is built from, so it matches the
/// other gallery buttons.
public final class VisualQuoteReplyButtonNode: ASDisplayNode {
    private let buttonView = ComponentView<Empty>()
    private var action: (() -> Void)?
    
    override public init() {
        super.init()
        
        // The glass group draws its title as an image, so VoiceOver gets the label from here.
        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
    }
    
    override public func accessibilityActivate() -> Bool {
        self.action?()
        return true
    }
    
    /// Lays out the button and returns its size.
    public func update(theme: PresentationTheme, title: String, action: @escaping () -> Void, transition: ContainedViewLayoutTransition) -> CGSize {
        self.action = action
        self.accessibilityLabel = title
        let size = self.buttonView.update(
            transition: ComponentTransition(transition),
            component: AnyComponent(GlassControlGroupComponent(
                theme: theme,
                preferClearGlass: false,
                background: .panel,
                items: [GlassControlGroupComponent.Item(
                    id: AnyHashable("reply"),
                    content: .text(title),
                    action: action
                )],
                minWidth: 44.0,
                textHorizontalInset: 16.0
            )),
            environment: {},
            containerSize: CGSize(width: 240.0, height: 44.0)
        )
        if let view = self.buttonView.view {
            if view.superview == nil {
                self.view.addSubview(view)
            }
            ComponentTransition(transition).setFrame(view: view, frame: CGRect(origin: CGPoint(), size: size))
        }
        return size
    }
}
