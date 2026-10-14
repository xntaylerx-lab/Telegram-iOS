import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import RadialStatusNode
import PhotoResources
import AppBundle
import StickerPackPreviewUI
import OverlayStatusController
import PresentationDataUtils
import ImageContentAnalysis
import TextSelectionNode
import Speak
import TranslateUI
import UndoUI
import ContextUI
import SaveToCameraRoll
import Pasteboard
import ChatRichTextEditorComposer
import AdUI
import AdsInfoScreen
import AdsReportScreen
import GlassBackgroundComponent
import ComponentFlow
import ComponentDisplayAdapters
import VisualQuote

/// Upper bound on the pixel dimensions a full-screen photo is decoded and rasterized at.
/// Photos larger than this are downscaled to fit; smaller ones are left untouched.
private let fullScreenImageMaxSize = CGSize(width: 4096.0, height: 4096.0)

enum ChatMediaGalleryThumbnail: Equatable {
    case image(ImageMediaReference)
    case video(FileMediaReference)
    case file(FileMediaReference)
    
    static func ==(lhs: ChatMediaGalleryThumbnail, rhs: ChatMediaGalleryThumbnail) -> Bool {
        switch lhs {
            case let .image(lhsImage):
                if case let .image(rhsImage) = rhs, lhsImage.media.isEqual(to: rhsImage.media) {
                    return true
                } else {
                    return false
                }
            case let .video(lhsVideo):
                if case let .video(rhsVideo) = rhs, lhsVideo.media.isEqual(to: rhsVideo.media) {
                    return true
                } else {
                    return false
                }
            case let .file(lhsFile):
                if case let .file(rhsFile) = rhs, lhsFile.media.isEqual(to: rhsFile.media) {
                    return true
                } else {
                    return false
                }
        }
    }
}

final class ChatMediaGalleryThumbnailItem: GalleryThumbnailItem {
    private let account: Account
    private let userLocation: MediaResourceUserLocation
    private let thumbnail: ChatMediaGalleryThumbnail
    
    init?(account: Account, userLocation: MediaResourceUserLocation, mediaReference: AnyMediaReference) {
        self.account = account
        self.userLocation = userLocation
        if let imageReference = mediaReference.concrete(TelegramMediaImage.self) {
            self.thumbnail = .image(imageReference)
        } else if let fileReference = mediaReference.concrete(TelegramMediaFile.self) {
            if fileReference.media.isVideo {
                self.thumbnail = .video(fileReference)
            } else {
                self.thumbnail = .file(fileReference)
            }
        } else {
            return nil
        }
    }
    
    func isEqual(to: GalleryThumbnailItem) -> Bool {
        if let to = to as? ChatMediaGalleryThumbnailItem {
            return self.thumbnail == to.thumbnail
        } else {
            return false
        }
    }
    
    func image(synchronous: Bool) -> (Signal<(TransformImageArguments) -> DrawingContext?, NoError>, CGSize) {
        switch self.thumbnail {
            case let .image(imageReference):
                if let representation = largestImageRepresentation(imageReference.media.representations) {
                    return (mediaGridMessagePhoto(account: self.account, userLocation: self.userLocation, photoReference: imageReference), representation.dimensions.cgSize)
                } else {
                    return (.single({ _ in return nil }), CGSize(width: 128.0, height: 128.0))
                }
            case let .video(fileReference):
                if let representation = largestImageRepresentation(fileReference.media.previewRepresentations) {
                    return (mediaGridMessageVideo(postbox: self.account.postbox, userLocation: self.userLocation, videoReference: fileReference), representation.dimensions.cgSize)
                } else if let dimensions = fileReference.media.dimensions {
                    return (mediaGridMessageVideo(postbox: self.account.postbox, userLocation: self.userLocation, videoReference: fileReference), dimensions.cgSize)
                } else {
                    return (.single({ _ in return nil }), CGSize(width: 128.0, height: 128.0))
                }
            case let .file(fileReference):
                if let representation = smallestImageRepresentation(fileReference.media.previewRepresentations) {
                    return (chatWebpageSnippetFile(account: self.account, userLocation: self.userLocation, mediaReference: fileReference.abstract, representation: representation), representation.dimensions.cgSize)
                } else {
                    return (.single({ _ in return nil }), CGSize(width: 128.0, height: 128.0))
                }
        }
    }
}

class ChatImageGalleryItem: GalleryItem {
    var id: AnyHashable {
        return self.message.stableId
    }
    
    let context: AccountContext
    let presentationData: PresentationData
    let message: Message
    let mediaSubject: GalleryMediaSubject?
    let location: MessageHistoryEntryLocation?
    let translateToLanguage: String?
    let peerIsCopyProtected: Bool
    let isSecret: Bool
    let displayInfoOnTop: Bool
    let performAction: (GalleryControllerInteractionTapAction) -> Void
    let openActionOptions: (GalleryControllerInteractionTapAction, Message) -> Void
    let sendSticker: ((FileMediaReference) -> Void)?
    let present: (ViewController, Any?) -> Void
    
    init(context: AccountContext, presentationData: PresentationData, message: Message, mediaSubject: GalleryMediaSubject? = nil, location: MessageHistoryEntryLocation?, translateToLanguage: String? = nil, peerIsCopyProtected: Bool = false, isSecret: Bool = false, displayInfoOnTop: Bool, performAction: @escaping (GalleryControllerInteractionTapAction) -> Void, openActionOptions: @escaping (GalleryControllerInteractionTapAction, Message) -> Void, sendSticker: ((FileMediaReference) -> Void)?, present: @escaping (ViewController, Any?) -> Void) {
        self.context = context
        self.presentationData = presentationData
        self.message = message
        self.mediaSubject = mediaSubject
        self.location = location
        self.translateToLanguage = translateToLanguage
        self.peerIsCopyProtected = peerIsCopyProtected
        self.isSecret = isSecret
        self.displayInfoOnTop = displayInfoOnTop
        self.performAction = performAction
        self.openActionOptions = openActionOptions
        self.sendSticker = sendSticker
        self.present = present
    }
    
    func node(synchronous: Bool) -> GalleryItemNode {
        let node = ChatImageGalleryItemNode(context: self.context, presentationData: self.presentationData, performAction: self.performAction, openActionOptions: self.openActionOptions, sendSticker: self.sendSticker, present: self.present)
        
        node.setMessage(self.message, mediaSubject: self.mediaSubject, displayInfo: !self.displayInfoOnTop, translateToLanguage: self.translateToLanguage, peerIsCopyProtected: self.peerIsCopyProtected, isSecret: self.isSecret, location: self.location)
        if let (media, _) = selectedMediaAndMediaImageForMessage(message: self.message, mediaSubject: self.mediaSubject) {
            if let image = media as? TelegramMediaImage {
                node.setImage(userLocation: .peer(self.message.id.peerId), imageReference: .message(message: MessageReference(self.message), media: image))
            } else if let file = media as? TelegramMediaFile, file.mimeType.hasPrefix("image/") {
                node.setFile(context: self.context, userLocation: .peer(self.message.id.peerId), fileReference: .message(message: MessageReference(self.message), media: file))
            }
        }
        
        return node
    }
    
    func updateNode(node: GalleryItemNode, synchronous: Bool) {
        if let node = node as? ChatImageGalleryItemNode, let location = self.location {
            node.setMessage(self.message, mediaSubject: self.mediaSubject, displayInfo: !self.displayInfoOnTop, translateToLanguage: self.translateToLanguage, peerIsCopyProtected: self.peerIsCopyProtected, isSecret: self.isSecret, location: location)
        }
    }
    
    func thumbnailItem() -> (Int64, GalleryThumbnailItem)? {
        if let paidContent = self.message.paidContent {
            var mediaReference: AnyMediaReference?
            var mediaIndex: Int = 0
            if case let .paidMediaIndex(index) = self.mediaSubject {
                mediaIndex = index
            }
            if case let .full(fullMedia) = paidContent.extendedMedia[Int(mediaIndex)], let m = fullMedia as? TelegramMediaImage {
                mediaReference = .message(message: MessageReference(self.message), media: m)
            }
            if let mediaReference {
                if let item = ChatMediaGalleryThumbnailItem(account: self.context.account, userLocation: .peer(self.message.id.peerId), mediaReference: mediaReference) {
                    return (0, item)
                }
            }
        } else if let poll = self.message.media.first(where: { $0 is TelegramMediaPoll }) as? TelegramMediaPoll, case let .pollOption(opaqueIdentifier) = self.mediaSubject {
            var mediaReference: AnyMediaReference?
            if let optionMedia = poll.options.first(where: { $0.opaqueIdentifier == opaqueIdentifier })?.media as? TelegramMediaImage {
                mediaReference = .message(message: MessageReference(self.message), media: optionMedia)
            }
            if let mediaReference {
                if let item = ChatMediaGalleryThumbnailItem(account: self.context.account, userLocation: .peer(self.message.id.peerId), mediaReference: mediaReference) {
                    return (0, item)
                }
            }
        } else if let id = self.message.groupInfo?.stableId {
            var mediaReference: AnyMediaReference?
            for m in self.message.media {
                if let m = m as? TelegramMediaImage {
                    mediaReference = .message(message: MessageReference(self.message), media: m)
                } else if let m = m as? TelegramMediaFile {
                    mediaReference = .message(message: MessageReference(self.message), media: m)
                }
            }
            if let mediaReference {
                if let item = ChatMediaGalleryThumbnailItem(account: self.context.account, userLocation: .peer(self.message.id.peerId), mediaReference: mediaReference) {
                    return (Int64(id), item)
                }
            }
        }
        return nil
    }
}

final class ChatImageGalleryItemNode: ZoomableContentGalleryItemNode {
    private let context: AccountContext
    private var message: Message?
    private var mediaSubject: GalleryMediaSubject?
    private var displayInfo: Bool = false
    private var translateToLanguage: String?
    private var peerIsCopyProtected: Bool = false
    private var isSecret: Bool = false
    private let presentationData: PresentationData
    
    private var sendSticker: ((FileMediaReference) -> Void)?
    
    private let imageNode: TransformImageNode
    private var recognizedContentNode: RecognizedContentContainer?
    
    private let recognitionOverlayContentNode: ImageRecognitionOverlayContentNode
    
    private var displayTextRecognitionButton: Bool = false
    private var displayStickersButton: Bool = false
    
    private let moreBarButton: MoreHeaderButton
    
    private var tilingNode: TilingNode?
    
    private var visualQuoteFrameNode: VisualQuoteFrameNode?
    private var visualQuotePreviousPanMinimumTouches: Int?
    private var visualQuoteReplyButton: VisualQuoteReplyButtonNode?
    private var visualQuoteHighlightNode: VisualQuoteFrameNode?
    private var visualQuoteControlsInset: UIEdgeInsets?
    private var visualQuoteNavigationBarHeight: CGFloat = 0.0
    private var visualQuoteLayoutSize: CGSize?
    private var visualQuoteRegion: VisualQuoteRegion?
    private var visualQuoteDetectionId: Int = 0
    
    fileprivate let _ready = Promise<Void>()
    fileprivate let _title = Promise<String>()
    fileprivate let _titleContent = Promise<GalleryTitleView.Content?>(nil)
    fileprivate let _rightBarButtonItems = Promise<[UIBarButtonItem]?>(nil)
    private let statusNodeContainer: HighlightableButtonNode
    private let statusNode: RadialStatusNode
    private let footerContentNode: ChatItemGalleryFooterContentNode
    
    private var contextAndMedia: (AccountContext, AnyMediaReference)?
    
    private var fetchDisposable = MetaDisposable()
    private let statusDisposable = MetaDisposable()
    private let dataDisposable = MetaDisposable()
    private let recognitionDisposable = MetaDisposable()
    private var status: EngineMediaResource.FetchStatus?
    private var fetchedDimensions: PixelDimensions?
    
    private let pagingEnabledPromise = ValuePromise<Bool>(true)
    
    private var currentSpeechHolder: SpeechSynthesizerHolder?
    
    override var baseNavigationController: () -> NavigationController? {
        didSet {
            if let _ = self.baseNavigationController() {
                self.moreBarButton.isHidden = false
            } else {
                self.moreBarButton.isHidden = true
            }
        }
    }
    
    init(context: AccountContext, presentationData: PresentationData, performAction: @escaping (GalleryControllerInteractionTapAction) -> Void, openActionOptions: @escaping (GalleryControllerInteractionTapAction, Message) -> Void, sendSticker: ((FileMediaReference) -> Void)?, present: @escaping (ViewController, Any?) -> Void) {
        self.context = context
        self.presentationData = presentationData
        self.sendSticker = sendSticker
        
        self.imageNode = TransformImageNode()
        self.imageNode.contentAnimations = .subsequentUpdates
        self.footerContentNode = ChatItemGalleryFooterContentNode(context: context, presentationData: presentationData, present: present)
        self.footerContentNode.performAction = performAction
        self.footerContentNode.openActionOptions = openActionOptions
        
        self.recognitionOverlayContentNode = ImageRecognitionOverlayContentNode(theme: presentationData.theme)
        
        self.statusNodeContainer = HighlightableButtonNode()
        self.statusNode = RadialStatusNode(backgroundNodeColor: UIColor(white: 0.0, alpha: 0.5))
        self.statusNode.frame = CGRect(origin: CGPoint(), size: CGSize(width: 50.0, height: 50.0))
        self.statusNode.isHidden = true
        
        self.moreBarButton = MoreHeaderButton()
        self.moreBarButton.isUserInteractionEnabled = true
        self.moreBarButton.setContent(.more(optionsCircleImage(dark: false)))
        
        super.init()
        
        self.clipsToBounds = true
        
        self.imageNode.imageUpdated = { [weak self] _ in
            self?._ready.set(.single(Void()))
        }
        
        self.imageNode.view.contentMode = .scaleAspectFill
        self.imageNode.clipsToBounds = true
        
        self.statusNodeContainer.addSubnode(self.statusNode)
        self.addSubnode(self.statusNodeContainer)
        
        self.statusNodeContainer.addTarget(self, action: #selector(self.statusPressed), forControlEvents: .touchUpInside)
        
        self.statusNodeContainer.isUserInteractionEnabled = false
        
        self.recognitionOverlayContentNode.action = { [weak self] active in
            if let strongSelf = self {
                let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut)
                if let recognizedContentNode = strongSelf.recognizedContentNode {
                    strongSelf.imageNode.isUserInteractionEnabled = active
                    transition.updateAlpha(node: recognizedContentNode, alpha: active ? 1.0 : 0.0)
                    if active {
                        strongSelf.updateControlsVisibility(false)
                    } else {
                        recognizedContentNode.dismissSelection()
                        strongSelf.updateControlsVisibility(true)
                    }
                    strongSelf.pagingEnabledPromise.set(!active)
                }
            }
        }
        
        self.moreBarButton.addTarget(self, action: #selector(self.moreButtonPressed), forControlEvents: .touchUpInside)
        self.moreBarButton.contextAction = { [weak self] sourceNode, gesture in
            self?.openMoreMenu(sourceNode: sourceNode, gesture: gesture)
        }
    }
    
    override func isPagingEnabled() -> Signal<Bool, NoError> {
        return self.pagingEnabledPromise.get()
    }
    
    deinit {
        //self.fetchDisposable.dispose()
        self.statusDisposable.dispose()
        self.dataDisposable.dispose()
        self.recognitionDisposable.dispose()
    }
    
    override func ready() -> Signal<Void, NoError> {
        return self._ready.get()
    }
    
    override func screenFrameUpdated(_ frame: CGRect) {
        let center = frame.midX - self.frame.width / 2.0
        self.subnodeTransform = CATransform3DMakeTranslation(-center * 0.16, 0.0, 0.0)
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition)
        
        let statusSize = CGSize(width: 50.0, height: 50.0)
        transition.updateFrame(node: self.statusNodeContainer, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - statusSize.width) / 2.0), y: floor((layout.size.height - statusSize.height) / 2.0)), size: statusSize))
        transition.updateFrame(node: self.statusNode, frame: CGRect(origin: CGPoint(), size: statusSize))
        
        self.visualQuoteNavigationBarHeight = navigationBarHeight
        if self.visualQuoteControlsInset != nil && self.visualQuoteLayoutSize != layout.size {
            // The zoom was reset for the new size, so the room made for the controls is no longer right.
            self.visualQuoteControlsInset = nil
            self.scrollNode.view.contentInset = UIEdgeInsets()
        }
        self.visualQuoteLayoutSize = layout.size
        self.updateVisualQuoteLayout(transition: transition)
    }
    
    private func setupImageRecognition(_ generate: @escaping (TransformImageArguments) -> DrawingContext?, dimensions: PixelDimensions) {
        guard let message = self.message, !message.isCopyProtected() && message.paidContent == nil else {
            return
        }
        let displaySize = dimensions.cgSize.fitted(CGSize(width: 1280.0, height: 1280.0)).dividedByScreenScale().integralFloor
        
        self.recognitionDisposable.set((recognizedContent(context: self.context, image: { return generate(TransformImageArguments(corners: ImageCorners(), imageSize: displaySize, boundingSize: displaySize, intrinsicInsets: UIEdgeInsets()))?.generateImage() }, messageId: message.id)
        |> deliverOnMainQueue).start(next: { [weak self] results in
            if let strongSelf = self {
                strongSelf.recognizedContentNode?.removeFromSupernode()
                if !results.isEmpty {
                    let size = strongSelf.imageNode.bounds.size
                    let recognizedContentNode = RecognizedContentContainer(size: size, recognitions: results, presentationData: strongSelf.context.sharedContext.currentPresentationData.with { $0 }, present: { [weak self] c, a in
                        if let strongSelf = self {
                            strongSelf.galleryController()?.presentInGlobalOverlay(c, with: a)
                        }
                    }, performAction: { [weak self] string, action in
                        guard let strongSelf = self else {
                            return
                        }
                        switch action {
                        case .copy:
                            UIPasteboard.general.string = string
                            if let controller = strongSelf.baseNavigationController()?.topViewController as? ViewController {
                                let presentationData = strongSelf.context.sharedContext.currentPresentationData.with({ $0 })
                                let tooltipController = UndoOverlayController(presentationData: presentationData, content: .copy(text: presentationData.strings.Conversation_TextCopied), elevatedLayout: true, animateInAsReplacement: false, action: { _ in return false })
                                controller.present(tooltipController, in: .window(.root))
                            }
                        case .share:
                            if let controller = strongSelf.baseNavigationController()?.topViewController as? ViewController {
                                let shareController = strongSelf.context.sharedContext.makeShareController(context: strongSelf.context, params: ShareControllerParams(subject: .text(string), externalShare: true, immediateExternalShare: false, updatedPresentationData: (strongSelf.context.sharedContext.currentPresentationData.with({ $0 }), strongSelf.context.sharedContext.presentationData)))
                                controller.present(shareController, in: .window(.root))
                            }
                        case .lookup:
                            let controller = UIReferenceLibraryViewController(term: string)
                            if let window = strongSelf.baseNavigationController()?.view.window {
                                controller.popoverPresentationController?.sourceView = window
                                controller.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
                                window.rootViewController?.present(controller, animated: true)
                            }
                        case .speak:
                            if let speechHolder = speakText(text: string) {
                                speechHolder.completion = { [weak self, weak speechHolder] in
                                    if let strongSelf = self, strongSelf.currentSpeechHolder == speechHolder {
                                        strongSelf.currentSpeechHolder = nil
                                    }
                                }
                                strongSelf.currentSpeechHolder = speechHolder
                            }
                        case .translate:
                            if let parentController = strongSelf.baseNavigationController()?.topViewController as? ViewController {
                                Task { @MainActor [weak parentController, weak strongSelf] in
                                    guard let strongSelf else {
                                        return
                                    }
                                    let presentationData = strongSelf.context.sharedContext.currentPresentationData.with({ $0 })
                                    let controller = await strongSelf.context.sharedContext.makeTextProcessingScreen(
                                        context: strongSelf.context,
                                        theme: nil,
                                        mode: .translate(fromLanguage: nil, applyResult: nil),
                                        inputText: .plain(text: string, entities: []),
                                        copyResult: { [weak parentController] text in
                                            storeComposedRichMessageInPasteboard(text)
                                            let tooltipController = UndoOverlayController(presentationData: presentationData, content: .copy(text: presentationData.strings.Conversation_TextCopied), elevatedLayout: true, animateInAsReplacement: false, action: { _ in return false })
                                            parentController?.present(tooltipController, in: .window(.root))
                                        },
                                        translateChat: nil
                                    )
                                    parentController?.present(controller, in: .window(.root))
                                }
                            }
                        }
                    })
                    recognizedContentNode.barcodeAction = { [weak self] payload, rect in
                        guard let strongSelf = self, let message = strongSelf.message else {
                            return
                        }
                        strongSelf.footerContentNode.openActionOptions?(.url(url: payload, concealed: true, forceExternal: false, dismiss: true), message)
                    }
                    recognizedContentNode.alpha = 0.0
                    recognizedContentNode.frame = CGRect(origin: CGPoint(), size: size)
                    recognizedContentNode.update(size: strongSelf.imageNode.bounds.size, transition: .immediate)
                    strongSelf.imageNode.addSubnode(recognizedContentNode)
                    strongSelf.recognizedContentNode = recognizedContentNode
                    strongSelf.recognitionOverlayContentNode.transitionIn()
                    
                    if !strongSelf.displayTextRecognitionButton {
                        strongSelf.displayTextRecognitionButton = true
                        strongSelf.updateFooter(animated: true)
                    }
                }
            }
        }))
    }
    
    fileprivate func setMessage(_ message: Message, mediaSubject: GalleryMediaSubject?, displayInfo: Bool, translateToLanguage: String?, peerIsCopyProtected: Bool, isSecret: Bool, location: MessageHistoryEntryLocation?) {
        if self.message?.id != message.id {
            self.clearVisualQuoteSelection(animated: false)
        }
        self.message = message
        self.mediaSubject = mediaSubject
        self.displayInfo = displayInfo
        self.translateToLanguage = translateToLanguage
        self.peerIsCopyProtected = peerIsCopyProtected
        self.isSecret = isSecret
        self.imageNode.captureProtected = message.id.peerId.namespace == Namespaces.Peer.SecretChat || message.isCopyProtected() || peerIsCopyProtected || isSecret || message.paidContent != nil
        self.updateFooter(animated: false)
        
        if self.isVisualQuoteEnabled && self.isVisualQuoteSupported {
            VisualQuoteDetector.prepare(context: self.context)
        }
        
        var title: String?
        if let _ = message.adAttribute {
            title = self.presentationData.strings.Gallery_Ad
        } else if let location {
            title = self.presentationData.strings.Items_NOfM("\(location.index + 1)", "\(location.count)").string
        }
        
        self._titleContent.set(.single(GalleryTitleView.Content(message: EngineMessage(message), title: title, action: message.adAttribute == nil ? { [weak self] in
            guard let self else {
                return
            }
            guard let controller = self.galleryController() as? GalleryController else {
                return
            }
            controller.dismissAndNavigateToMessageContext(message: message)
        } : nil)))
    }
    
    private func updateFooter(animated: Bool) {
        guard let message = self.message else {
            return
        }
        self.footerContentNode.setMessage(message, mediaSubject: self.mediaSubject, displayInfo: self.displayInfo, translateToLanguage: self.translateToLanguage, peerIsCopyProtected: self.peerIsCopyProtected, displayTextRecognitionButton: self.displayTextRecognitionButton, displayStickersButton: self.displayStickersButton, animated: animated)
    }
    
    fileprivate func setImage(userLocation: MediaResourceUserLocation, imageReference: ImageMediaReference) {
        if self.contextAndMedia == nil || !self.contextAndMedia!.1.media.isEqual(to: imageReference.media) {
            if let largestSize = largestRepresentationForPhoto(imageReference.media, maxSize: PixelDimensions(fullScreenImageMaxSize)) {
                let displaySize = largestSize.dimensions.cgSize.fitted(fullScreenImageMaxSize).dividedByScreenScale().integralFloor
                self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: displaySize, boundingSize: displaySize, intrinsicInsets: UIEdgeInsets()))()
                let signal: Signal<(TransformImageArguments) -> DrawingContext?, NoError> = chatMessagePhotoInternal(photoData: chatMessagePhotoDatas(postbox: self.context.account.postbox, userLocation: userLocation, photoReference: imageReference, fullRepresentationSize: fullScreenImageMaxSize, tryAdditionalRepresentations: true, synchronousLoad: false), synchronousLoad: false)
                |> map { [weak self] _, quality, generate -> (TransformImageArguments) -> DrawingContext? in
                    Queue.mainQueue().async {
                        guard let strongSelf = self else {
                            return
                        }
                        switch quality {
                        case .medium, .full:
                            strongSelf.statusNodeContainer.isHidden = true
                            
                            if !imageReference.media.flags.contains(.hasStickers) {
                                Queue.concurrentDefaultQueue().async {
                                    strongSelf.setupImageRecognition(generate, dimensions: largestSize.dimensions)
                                }
                            }
                        case .none, .blurred:
                            strongSelf.statusNodeContainer.isHidden = false
                        }
                    }
                    return generate
                }
                self.imageNode.setSignal(signal)
                
                self.zoomableContent = (largestSize.dimensions.cgSize, self.imageNode)
                
                self.fetchDisposable.set(self.context.engine.resources.fetch(reference: imageReference.resourceReference(largestSize.resource), userLocation: userLocation, userContentType: .image).start())
                self.setupStatus(resource: largestSize.resource)
            } else {
                self._ready.set(.single(Void()))
            }
            
            var barButtonItems: [UIBarButtonItem] = []
            if imageReference.media.flags.contains(.hasStickers) {
                self.displayStickersButton = true
            }
            if self.message != nil {
                let moreMenuItem = UIBarButtonItem(customDisplayNode: self.moreBarButton)!
                moreMenuItem.accessibilityLabel = self.presentationData.strings.Common_More
                barButtonItems.append(moreMenuItem)
            }
            self._rightBarButtonItems.set(.single(barButtonItems))
        }
        self.contextAndMedia = (self.context, imageReference.abstract)
        self.updateFooter(animated: false)
    }
    
    private func updateImageFromFile(path: String) {
        if let _ = self.tilingNode {
            self.tilingNode = nil
        }
        
        guard let dataProvider = CGDataProvider(url: URL(fileURLWithPath: path) as CFURL) else {
            self._ready.set(.single(Void()))
            return
        }
        
        var maybeImage: CGImage?
        
        if let image = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            maybeImage = image
        } else if let image = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            maybeImage = image
        }
        
        guard let image = maybeImage else {
            self._ready.set(.single(Void()))
            return
        }
        
        let tilingNode = TilingNode(image: image, path: path)
        self.tilingNode = tilingNode
        
        let size = CGSize(width: image.width, height: image.height)
        self.zoomableContent = (size, tilingNode)
        
        self._ready.set(.single(Void()))
    }
    
    @objc private func moreButtonPressed() {
        self.moreBarButton.play()
        self.moreBarButton.contextAction?(self.moreBarButton.containerNode, nil)
    }
    
    private func adMenuMainItems() -> Signal<[ContextMenuItem], NoError> {
        guard let message = self.message, let adAttribute = message.adAttribute else {
            return .single([])
        }
        
        let context = self.context
        let presentationData = self.presentationData
        var actions: [ContextMenuItem] = []
        if adAttribute.canReport {
            actions.append(.action(ContextMenuActionItem(text: presentationData.strings.Chat_ContextMenu_AboutAd, textColor: .primary, textLayout: .twoLinesMax, textFont: .custom(font: Font.regular(presentationData.listsFontSize.baseDisplaySize - 1.0), height: nil, verticalOffset: nil), badge: nil, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Info"), color: theme.actionSheet.primaryTextColor)
            }, iconSource: nil, action: { [weak self] _, f in
                f(.dismissWithoutContent)
                if let navigationController = self?.baseNavigationController() as? NavigationController {
                    navigationController.pushViewController(AdsInfoScreen(context: context, mode: .channel))
                }
            })))
            
            actions.append(.action(ContextMenuActionItem(text: presentationData.strings.Chat_ContextMenu_ReportAd, textColor: .primary, textLayout: .twoLinesMax, textFont: .custom(font: Font.regular(presentationData.listsFontSize.baseDisplaySize - 1.0), height: nil, verticalOffset: nil), badge: nil, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Restrict"), color: theme.actionSheet.primaryTextColor)
            }, iconSource: nil, action: { [weak self] _, f in
                f(.default)
                
                let _ = (context.engine.messages.reportAdMessage(opaqueId: adAttribute.opaqueId, option: nil)
                |> deliverOnMainQueue).start(next: { [weak self] result in
                    if case let .options(title, options) = result {
                        if let navigationController = self?.baseNavigationController() as? NavigationController {
                            navigationController.pushViewController(
                                AdsReportScreen(
                                    context: context,
                                    opaqueId: adAttribute.opaqueId,
                                    title: title,
                                    options: options,
                                    forceDark: true,
                                    completed: {
                                        if let navigationController = self?.baseNavigationController() as? NavigationController, let chatController = navigationController.viewControllers.last as? ChatController {
                                            chatController.removeAd(opaqueId: adAttribute.opaqueId)
                                        }
                                    }
                                )
                            )
                        }
                    }
                })
            })))
            
            actions.append(.separator)
                           
            actions.append(.action(ContextMenuActionItem(text: presentationData.strings.Chat_ContextMenu_RemoveAd, textColor: .primary, textLayout: .twoLinesMax, textFont: .custom(font: Font.regular(presentationData.listsFontSize.baseDisplaySize - 1.0), height: nil, verticalOffset: nil), badge: nil, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Clear"), color: theme.actionSheet.primaryTextColor)
            }, iconSource: nil, action: { [weak self] c, _ in
                c?.dismiss(completion: {
                    var replaceImpl: ((ViewController) -> Void)?
                    let controller = context.sharedContext.makePremiumDemoController(context: context, subject: .noAds, forceDark: true, action: {
                        let controller = context.sharedContext.makePremiumIntroController(context: context, source: .ads, forceDark: true, dismissed: nil)
                        replaceImpl?(controller)
                    }, dismissed: nil)
                    replaceImpl = { [weak controller] c in
                        controller?.replace(with: c)
                    }
                    if let navigationController = self?.baseNavigationController() as? NavigationController {
                        navigationController.pushViewController(controller)
                    }
                })
            })))
        } else {
            actions.append(.action(ContextMenuActionItem(text: presentationData.strings.SponsoredMessageMenu_Info, textColor: .primary, textLayout: .twoLinesMax, textFont: .custom(font: Font.regular(presentationData.listsFontSize.baseDisplaySize - 1.0), height: nil, verticalOffset: nil), badge: nil, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Info"), color: theme.actionSheet.primaryTextColor)
            }, iconSource: nil, action: { [weak self] _, f in
                f(.dismissWithoutContent)
                if let navigationController = self?.baseNavigationController() as? NavigationController {
                    navigationController.pushViewController(AdInfoScreen(context: context, forceDark: true))
                }
            })))
            
            let premiumConfiguration = PremiumConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
            if !context.isPremium && !premiumConfiguration.isPremiumDisabled {
                actions.append(.action(ContextMenuActionItem(text: presentationData.strings.SponsoredMessageMenu_Hide, textColor: .primary, textLayout: .twoLinesMax, textFont: .custom(font: Font.regular(presentationData.listsFontSize.baseDisplaySize - 1.0), height: nil, verticalOffset: nil), badge: nil, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Clear"), color: theme.actionSheet.primaryTextColor)
                }, iconSource: nil, action: { [weak self] c, _ in
                    c?.dismiss(completion: {
                        var replaceImpl: ((ViewController) -> Void)?
                        let controller = context.sharedContext.makePremiumDemoController(context: context, subject: .noAds, forceDark: true, action: {
                            let controller = context.sharedContext.makePremiumIntroController(context: context, source: .ads, forceDark: true, dismissed: nil)
                            replaceImpl?(controller)
                        }, dismissed: nil)
                        replaceImpl = { [weak controller] c in
                            controller?.replace(with: c)
                        }
                        if let navigationController = self?.baseNavigationController() as? NavigationController {
                            navigationController.pushViewController(controller)
                        }
                    })
                })))
            }
            
            if !message.text.isEmpty {
                actions.append(.separator)
                actions.append(.action(ContextMenuActionItem(text: presentationData.strings.Conversation_ContextMenuCopy, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.actionSheet.primaryTextColor)
                }, action: { [weak self] _, f in
                    var messageEntities: [MessageTextEntity]?
                    for attribute in message.attributes {
                        if let attribute = attribute as? TextEntitiesMessageAttribute {
                            messageEntities = attribute.entities
                        }
                    }
                    
                    storeMessageTextInPasteboard(message.text, entities: messageEntities)
                    
                    Queue.mainQueue().after(0.2, {
                        guard let self, let controller = self.galleryController() else {
                            return
                        }
                        controller.present(UndoOverlayController(presentationData: self.presentationData, content: .copy(text: presentationData.strings.Conversation_MessageCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .window(.root))
                    })
                    
                    f(.default)
                })))
            }
        }

        return .single(actions)
    }

    private func contextMenuMainItems() -> Signal<[ContextMenuItem], NoError> {
        let peer: Signal<EnginePeer?, NoError>
        if let message = self.message {
            peer = self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: message.id.peerId))
        } else {
            peer = .single(nil)
        }
    
        let context = self.context
        return peer
        |> map { [weak self] peer -> [ContextMenuItem] in
            guard let self else {
                return []
            }
            var items: [ContextMenuItem] = []
            if let message = self.message {
                items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.SharedMedia_ViewInChat, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/GoToMessage"), color: theme.contextMenu.primaryColor)}, action: { [weak self] _, f in
                    if let self, let peer, let navigationController = self.baseNavigationController() {
                        self.beginCustomDismiss(.simpleAnimation)
                        
                        var innerSubject: EngineMessageReplyInnerSubject?
                        if let mediaSubject = self.mediaSubject, case let .pollOption(opaqueIdentifier) = mediaSubject {
                            innerSubject = .pollOption(opaqueIdentifier)
                        }
                        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil, subject: innerSubject), timecode: nil, setupReply: false)))
                        
                        Queue.mainQueue().after(0.3) {
                            self.completeCustomDismiss(false)
                        }
                    }
                    f(.default)
                })))
                
                if !message.isCopyProtected() && !self.peerIsCopyProtected && message.paidContent == nil, let media = self.contextAndMedia?.1 {
                    items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Gallery_CreateSticker, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Sticker"), color: theme.actionSheet.primaryTextColor) }, action: { [weak self] _, f in
                        f(.default)
                        guard let self else {
                            return
                        }
                        let _ = (fetchMediaData(context: context, userLocation: .other, mediaReference: media)
                        |> deliverOnMainQueue).start(next: { [weak self] (value, isImage) in
                            guard let self, case let .data(data) = value, data.isComplete, isImage, let image = UIImage(contentsOfFile: data.path) else {
                                return
                            }
                            let sendSticker = self.sendSticker
                            let controller = context.sharedContext.makeStickerEditorScreen(context: context, source: image, mode: .generic(canSend: self.sendSticker != nil), transitionArguments: (self.imageNode.view, self.imageNode.bounds, self.imageNode.image), completion: { file, _, commit in
                                sendSticker?(.standalone(media: file))
                                commit()
                            }, cancelled: {})
                            guard let galleryController = self.galleryController() as? GalleryController, let navigationController = self.baseNavigationController() else {
                                return
                            }
                            galleryController.willDismiss()
                            (navigationController.topViewController as? ViewController)?.present(controller, in: .window(.root))
                            (controller as? MediaEditorScreen)?.customNavigationController  = navigationController
                            self.imageNode.isHidden = true
                            Queue.mainQueue().after(0.5, {
                                galleryController.dismiss()
                            })
                        })
                    })))
                    
                    items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Gallery_SaveImage, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Download"), color: theme.actionSheet.primaryTextColor) }, action: { [weak self] _, f in
                        f(.default)
                                                
                        let _ = (SaveToCameraRoll.saveToCameraRoll(context: context, userLocation: .peer(message.id.peerId), mediaReference: media)
                        |> deliverOnMainQueue).start(completed: { [weak self] in
                            guard let strongSelf = self else {
                                return
                            }
                            guard let controller = strongSelf.galleryController() else {
                                return
                            }
                            controller.present(UndoOverlayController(presentationData: strongSelf.presentationData, content: .mediaSaved(text: strongSelf.presentationData.strings.Gallery_ImageSaved), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .window(.root))
                        })
                    })))
                }
            }
            
            if let peer, let message = self.message, canSendMessagesToPeer(peer) {
                items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Conversation_ContextMenuReply, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Reply"), color: theme.contextMenu.primaryColor)}, action: { [weak self] _, f in
                    if let self, let navigationController = self.baseNavigationController() {
                        self.beginCustomDismiss(.simpleAnimation)
                        
                        var innerSubject: EngineMessageReplyInnerSubject?
                        if let mediaSubject = self.mediaSubject, case let .pollOption(opaqueIdentifier) = mediaSubject {
                            innerSubject = .pollOption(opaqueIdentifier)
                        }
                        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil, subject: innerSubject), timecode: nil, setupReply: true)))
                        
                        Queue.mainQueue().after(0.3) {
                            self.completeCustomDismiss(false)
                        }
                    }
                    f(.default)
                })))
            }
            
            if self.canDelete() {
                items.append(.action(ContextMenuActionItem(text: self.presentationData.strings.Common_Delete, textColor: .destructive, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor) }, action: { [weak self] _, f in
                    f(.default)

                    if let strongSelf = self {
                        strongSelf.footerContentNode.deleteButtonPressed()
                    }
                })))
            }
            return items
        }
    }
    
    private func openMoreMenu(sourceNode: ASDisplayNode, gesture: ContextGesture?) {
        let items: Signal<[ContextMenuItem], NoError>
        if let message = self.message, let _ = message.adAttribute {
            items = self.adMenuMainItems()
        } else {
            items = self.contextMenuMainItems()
        }
        guard let controller = self.baseNavigationController()?.topViewController as? ViewController else {
            return
        }
        
        var sourceView = self.moreBarButton.referenceNode.view
        if let value = self.galleryController()?.navigationBar?.navigationButtonContextContainer(sourceView: sourceView) {
            sourceView = value
        }
        
        let contextController = makeContextController(presentationData: self.presentationData.withUpdated(theme: defaultDarkColorPresentationTheme), source: .reference(HeaderContextReferenceContentSource(controller: controller, sourceView: sourceView, actionsOnTop: false)), items: items |> map { ContextController.Items(content: .list($0)) }, gesture: gesture)
        controller.presentInGlobalOverlay(contextController)
    }
    
    func textRecognitionButtonPressed() {
        self.recognitionOverlayContentNode.isSelected = true
        self.recognitionOverlayContentNode.action?(true)
    }
    
    @objc func openStickersButtonPressed() {
        guard let (context, media) = self.contextAndMedia else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with({ $0 }).withUpdated(theme: defaultDarkColorPresentationTheme)
        let topController = (self.baseNavigationController()?.topViewController as? ViewController)
        let progressSignal = Signal<Never, NoError> { subscriber in
            let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
            topController?.present(controller, in: .window(.root), with: nil)
            return ActionDisposable { [weak controller] in
                Queue.mainQueue().async() {
                    controller?.dismiss()
                }
            }
        }
        |> runOn(Queue.mainQueue())
        |> delay(0.15, queue: Queue.mainQueue())
        let progressDisposable = progressSignal.start()
        
        let signal = context.engine.stickers.stickerPacksAttachedToMedia(media: media)
        |> afterDisposed {
            Queue.mainQueue().async {
                progressDisposable.dispose()
            }
        }
        let _ = (signal
        |> deliverOnMainQueue).start(next: { [weak self] packs in
            guard let strongSelf = self, !packs.isEmpty else {
                return
            }
            let baseNavigationController = strongSelf.baseNavigationController()
            baseNavigationController?.view.endEditing(true)
            let controller = StickerPackScreen(context: context, updatedPresentationData: (initial: presentationData, signal: .single(presentationData)), mainStickerPack: packs[0], stickerPacks: packs, sendSticker: nil, actionPerformed: { actions in
                if let (info, items, action) = actions.first {
                    let animateInAsReplacement = false
                    switch action {
                    case .add:
                        topController?.present(UndoOverlayController(presentationData: presentationData, content: .stickersModified(title: presentationData.strings.StickerPackActionInfo_AddedTitle, text: presentationData.strings.StickerPackActionInfo_AddedText(info.title).string, undo: false, info: info, topItem: items.first, context: context), elevatedLayout: true, animateInAsReplacement: animateInAsReplacement, action: { _ in
                            return true
                        }), in: .window(.root))
                    case let .remove(positionInList):
                        topController?.present(UndoOverlayController(presentationData: presentationData, content: .stickersModified(title: presentationData.strings.StickerPackActionInfo_RemovedTitle, text: presentationData.strings.StickerPackActionInfo_RemovedText(info.title).string, undo: true, info: info, topItem: items.first, context: context), elevatedLayout: true, animateInAsReplacement: animateInAsReplacement, action: { action in
                            if case .undo = action {
                                let _ = context.engine.stickers.addStickerPackInteractively(info: info, items: items, positionInList: positionInList).start()
                            }
                            return true
                        }), in: .window(.root))
                    }
                }
            })
            (baseNavigationController?.topViewController as? ViewController)?.present(controller, in: .window(.root), with: nil)
        })
    }
    
    func setFile(context: AccountContext, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, force: Bool = false) {
        if self.contextAndMedia == nil || !self.contextAndMedia!.1.media.isEqual(to: fileReference.media) || force {
            if var largestSize = (fileReference.media.dimensions ?? self.fetchedDimensions) {
                var displaySize = largestSize.cgSize.dividedByScreenScale()
                if let previewDimensions = largestImageRepresentation(fileReference.media.previewRepresentations)?.dimensions {
                    let previewAspect = CGFloat(previewDimensions.width) / CGFloat(previewDimensions.height)
                    let aspect = displaySize.width / displaySize.height
                    if abs(previewAspect - 1.0 / aspect) < 0.1 {
                        displaySize = CGSize(width: displaySize.height, height: displaySize.width)
                        largestSize = PixelDimensions(width: largestSize.height, height: largestSize.width)
                    }
                }
                
                self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: displaySize, boundingSize: displaySize, intrinsicInsets: UIEdgeInsets()))()
                
                /*if largestSize.width > 2600 || largestSize.height > 2600 {
                    self.dataDisposable.set((self.context.account.postbox.mediaBox.resourceData(fileReference.media.resource)
                    |> deliverOnMainQueue).start(next: { [weak self] data in
                        guard let strongSelf = self else {
                            return
                        }
                        if !data.complete {
                            return
                        }
                        strongSelf.updateImageFromFile(path: data.path)
                    }))
                } else {*/
                
                let signal = chatMessageImageFile(account: context.account, userLocation: userLocation, fileReference: fileReference, thumbnail: false)
                |> afterNext({ [weak self] generate in
                    guard let self else {
                        return
                    }
                    Queue.concurrentDefaultQueue().async {
                        self.setupImageRecognition(generate, dimensions: largestSize)
                    }
                })
                
                    self.imageNode.setSignal(signal, dispatchOnDisplayLink: false)
                //}
                
                self.zoomableContent = (largestSize.cgSize, self.imageNode)
                self.setupStatus(resource: fileReference.media.resource)
                
                var barButtonItems: [UIBarButtonItem] = []
                if self.message != nil {
                    let moreMenuItem = UIBarButtonItem(customDisplayNode: self.moreBarButton)!
                    moreMenuItem.accessibilityLabel = self.presentationData.strings.Common_More
                    barButtonItems.append(moreMenuItem)
                }
                self._rightBarButtonItems.set(.single(barButtonItems))
                
                self.fetchDisposable.set(self.context.engine.resources.fetch(reference: fileReference.resourceReference(fileReference.media.resource), userLocation: userLocation, userContentType: .image).start())
            } else {
                let _ = (chatMessageFileDatas(account: context.account, userLocation: userLocation, fileReference: fileReference, progressive: false, fetched: true)
                |> mapToSignal { value -> Signal<UIImage?, NoError> in
                    if value._2, let path = value._1, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                        return .single(UIImage(data: data))
                    }
                    return .complete()
                }
                |> deliverOnMainQueue).start(next: { [weak self] image in
                    if let self, let image {
                        self.fetchedDimensions = PixelDimensions(image.size)
                        self.setFile(context: context, userLocation: userLocation, fileReference: fileReference, force: true)
                    }
                })
                
                
                
                self._ready.set(.single(Void()))
            }
        }
        self.contextAndMedia = (context, fileReference.abstract)
    }
    
    private func setupStatus(resource: MediaResource) {
        self.statusDisposable.set((self.context.engine.resources.status(resource: EngineMediaResource(resource))
        |> deliverOnMainQueue).start(next: { [weak self] status in
            if let strongSelf = self {
                let previousStatus = strongSelf.status
                strongSelf.status = status
                switch status {
                    case .Remote, .Paused:
                        strongSelf.statusNode.isHidden = false
                        strongSelf.statusNode.alpha = 1.0
                        strongSelf.statusNodeContainer.isUserInteractionEnabled = true
                        strongSelf.statusNode.transitionToState(.download(.white), completion: {})
                    case let .Fetching(_, progress):
                        strongSelf.statusNode.isHidden = false
                        strongSelf.statusNode.alpha = 1.0
                        strongSelf.statusNodeContainer.isUserInteractionEnabled = true
                        let adjustedProgress = max(progress, 0.027)
                        strongSelf.statusNode.transitionToState(.progress(color: .white, lineWidth: nil, value: CGFloat(adjustedProgress), cancelEnabled: true, animateRotation: true), completion: {})
                    case .Local:
                        if let previousStatus = previousStatus, case .Fetching = previousStatus {
                            strongSelf.statusNode.transitionToState(.progress(color: .white, lineWidth: nil, value: 1.0, cancelEnabled: true, animateRotation: true), completion: {
                                if let strongSelf = self {
                                    strongSelf.statusNode.alpha = 0.0
                                    strongSelf.statusNodeContainer.isUserInteractionEnabled = false
                                    strongSelf.statusNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { _ in
                                        if let strongSelf = self {
                                            strongSelf.statusNode.transitionToState(.none, animated: false, completion: {})
                                        }
                                    })
                                }
                            })
                        } else if !strongSelf.statusNode.isHidden && !strongSelf.statusNode.alpha.isZero {
                            strongSelf.statusNode.alpha = 0.0
                            strongSelf.statusNodeContainer.isUserInteractionEnabled = false
                            strongSelf.statusNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { _ in
                                if let strongSelf = self {
                                    strongSelf.statusNode.transitionToState(.none, animated: false, completion: {})
                                }
                            })
                        }
                }
            }
        }))
    }
    
    override func animateIn(from node: (ASDisplayNode, CGRect, () -> (UIView?, UIView?)), addToTransitionSurface: (UIView) -> Void, completion: @escaping () -> Void) {
        let contentNode = self.tilingNode ?? self.imageNode
        
        var transformedFrame = node.0.view.convert(node.0.view.bounds, to: contentNode.view)
        let transformedSuperFrame = node.0.view.convert(node.0.view.bounds, to: contentNode.view.superview)
        let transformedSelfFrame = node.0.view.convert(node.0.view.bounds, to: self.view)
        
        /*let projectedScale = CGPoint(x: contentNode.view.bounds.width / node.1.width, y: contentNode.view.bounds.height / node.1.height)
        let scaledLocalImageViewBounds = CGRect(x: -node.1.minX * projectedScale.x, y: -node.1.minY * projectedScale.y, width: node.0.bounds.width * projectedScale.x, height: node.0.bounds.height * projectedScale.y)*/
        
        let scaledLocalImageViewBounds = contentNode.view.bounds
        
        let transformedCopyViewFinalFrame = contentNode.view.convert(scaledLocalImageViewBounds, to: self.view)
        
        let (maybeSurfaceCopyView, _) = node.2()
        let (maybeCopyView, copyViewBackgrond) = node.2()
        copyViewBackgrond?.alpha = 0.0
        let surfaceCopyView = maybeSurfaceCopyView!
        let copyView = maybeCopyView!
        
        addToTransitionSurface(surfaceCopyView)
        
        var transformedSurfaceFrame: CGRect?
        var transformedSurfaceFinalFrame: CGRect?
        if let contentSurface = surfaceCopyView.superview {
            transformedSurfaceFrame = node.0.view.convert(node.0.view.bounds, to: contentSurface)
            transformedSurfaceFinalFrame = contentNode.view.convert(scaledLocalImageViewBounds, to: contentSurface)
        }
        
        if let transformedSurfaceFrame = transformedSurfaceFrame {
            surfaceCopyView.frame = transformedSurfaceFrame
        }
        
        //self.view.insertSubview(copyView, belowSubview: self.scrollNode.view)
        copyView.frame = transformedSelfFrame
        
        copyView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        
        surfaceCopyView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false)
        
        let positionDuration: Double = 0.21
        
        copyView.layer.animatePosition(from: CGPoint(x: transformedSelfFrame.midX, y: transformedSelfFrame.midY), to: CGPoint(x: transformedCopyViewFinalFrame.midX, y: transformedCopyViewFinalFrame.midY), duration: positionDuration, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { [weak copyView] _ in
            copyView?.removeFromSuperview()
        })
        let scale = CGSize(width: transformedCopyViewFinalFrame.size.width / transformedSelfFrame.size.width, height: transformedCopyViewFinalFrame.size.height / transformedSelfFrame.size.height)
        copyView.layer.animate(from: NSValue(caTransform3D: CATransform3DIdentity), to: NSValue(caTransform3D: CATransform3DMakeScale(scale.width, scale.height, 1.0)), keyPath: "transform", timingFunction: kCAMediaTimingFunctionSpring, duration: 0.25, removeOnCompletion: false)
        
        if let transformedSurfaceFrame = transformedSurfaceFrame, let transformedSurfaceFinalFrame = transformedSurfaceFinalFrame {
            surfaceCopyView.layer.animatePosition(from: CGPoint(x: transformedSurfaceFrame.midX, y: transformedSurfaceFrame.midY), to: CGPoint(x: transformedSurfaceFinalFrame.midX, y: transformedSurfaceFinalFrame.midY), duration: positionDuration, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { [weak surfaceCopyView] _ in
                surfaceCopyView?.removeFromSuperview()
            })
            let scale = CGSize(width: transformedSurfaceFinalFrame.size.width / transformedSurfaceFrame.size.width, height: transformedSurfaceFinalFrame.size.height / transformedSurfaceFrame.size.height)
            surfaceCopyView.layer.animate(from: NSValue(caTransform3D: CATransform3DIdentity), to: NSValue(caTransform3D: CATransform3DMakeScale(scale.width, scale.height, 1.0)), keyPath: "transform", timingFunction: kCAMediaTimingFunctionSpring, duration: 0.25, removeOnCompletion: false)
        }
        
        contentNode.layer.animatePosition(from: CGPoint(x: transformedSuperFrame.midX, y: transformedSuperFrame.midY), to: contentNode.layer.position, duration: positionDuration, timingFunction: kCAMediaTimingFunctionSpring)
        contentNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
        
        transformedFrame.origin = CGPoint()
        contentNode.layer.animateBounds(from: transformedFrame, to: contentNode.layer.bounds, duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring)
        
        self.statusNodeContainer.layer.animatePosition(from: CGPoint(x: transformedSuperFrame.midX, y: transformedSuperFrame.midY), to: self.statusNodeContainer.position, duration: positionDuration, timingFunction: kCAMediaTimingFunctionSpring)
        self.statusNodeContainer.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring)
        self.statusNodeContainer.layer.animateScale(from: 0.5, to: 1.0, duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring)
    }
    
    override func animateOut(to node: (ASDisplayNode, CGRect, () -> (UIView?, UIView?)), addToTransitionSurface: (UIView) -> Void, completion: @escaping () -> Void) {
        if let controller = self.baseNavigationController()?.topViewController as? ViewController {
            controller.window?.forEachController({ controller in
                if let controller = controller as? UndoOverlayController {
                    controller.dismissWithCommitAction()
                }
            })
            controller.forEachController({ controller in
                if let controller = controller as? UndoOverlayController {
                    controller.dismissWithCommitAction()
                }
                return true
            })
        }
        
        self.fetchDisposable.set(nil)
        
        let contentNode = self.tilingNode ?? self.imageNode
        
        var transformedFrame = node.0.view.convert(node.0.view.bounds, to: contentNode.view)
        let transformedSuperFrame = node.0.view.convert(node.0.view.bounds, to: contentNode.view.superview)
        let transformedSelfFrame = node.0.view.convert(node.0.view.bounds, to: self.view)
        let transformedCopyViewInitialFrame = contentNode.view.convert(contentNode.view.bounds, to: self.view)
        
        var positionCompleted = false
        var boundsCompleted = false
        var copyCompleted = false
        
        let (maybeSurfaceCopyView, _) = node.2()
        let (maybeCopyView, copyViewBackgrond) = node.2()
        copyViewBackgrond?.alpha = 0.0
        let surfaceCopyView = maybeSurfaceCopyView!
        let copyView = maybeCopyView!
        
        addToTransitionSurface(surfaceCopyView)
        
        var transformedSurfaceFrame: CGRect?
        var transformedSurfaceCopyViewInitialFrame: CGRect?
        if let contentSurface = surfaceCopyView.superview {
            transformedSurfaceFrame = node.0.view.convert(node.0.view.bounds, to: contentSurface)
            transformedSurfaceCopyViewInitialFrame = contentNode.view.convert(contentNode.view.bounds, to: contentSurface)
        }
        
        self.view.insertSubview(copyView, belowSubview: self.scrollNode.view)
        copyView.frame = transformedSelfFrame
        
        let intermediateCompletion = { [weak copyView, weak surfaceCopyView] in
            if positionCompleted && boundsCompleted && copyCompleted {
                copyView?.removeFromSuperview()
                surfaceCopyView?.removeFromSuperview()
                completion()
            }
        }
        
        copyView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.08, removeOnCompletion: false)
        surfaceCopyView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.025, removeOnCompletion: false)
        
        copyView.layer.animatePosition(from: CGPoint(x: transformedCopyViewInitialFrame.midX, y: transformedCopyViewInitialFrame.midY), to: CGPoint(x: transformedSelfFrame.midX, y: transformedSelfFrame.midY), duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        let scale = CGSize(width: transformedCopyViewInitialFrame.size.width / transformedSelfFrame.size.width, height: transformedCopyViewInitialFrame.size.height / transformedSelfFrame.size.height)
        copyView.layer.animate(from: NSValue(caTransform3D: CATransform3DMakeScale(scale.width, scale.height, 1.0)), to: NSValue(caTransform3D: CATransform3DIdentity), keyPath: "transform", timingFunction: kCAMediaTimingFunctionSpring, duration: 0.25, removeOnCompletion: false, completion: { _ in
            copyCompleted = true
            intermediateCompletion()
        })
        
        if let transformedSurfaceFrame = transformedSurfaceFrame, let transformedCopyViewInitialFrame = transformedSurfaceCopyViewInitialFrame {
            surfaceCopyView.layer.animatePosition(from: CGPoint(x: transformedCopyViewInitialFrame.midX, y: transformedCopyViewInitialFrame.midY), to: CGPoint(x: transformedSurfaceFrame.midX, y: transformedSurfaceFrame.midY), duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
            let scale = CGSize(width: transformedCopyViewInitialFrame.size.width / transformedSurfaceFrame.size.width, height: transformedCopyViewInitialFrame.size.height / transformedSurfaceFrame.size.height)
            surfaceCopyView.layer.animate(from: NSValue(caTransform3D: CATransform3DMakeScale(scale.width, scale.height, 1.0)), to: NSValue(caTransform3D: CATransform3DIdentity), keyPath: "transform", timingFunction: kCAMediaTimingFunctionSpring, duration: 0.25, removeOnCompletion: false)
        }
        
        contentNode.layer.animatePosition(from: contentNode.layer.position, to: CGPoint(x: transformedSuperFrame.midX, y: transformedSuperFrame.midY), duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
            positionCompleted = true
            intermediateCompletion()
        })
        
        contentNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.08, removeOnCompletion: false)
        
        transformedFrame.origin = CGPoint()
        contentNode.layer.animateBounds(from: contentNode.layer.bounds, to: transformedFrame, duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
            boundsCompleted = true
            intermediateCompletion()
        })
        
        self.statusNodeContainer.layer.animatePosition(from: self.statusNodeContainer.position, to: CGPoint(x: transformedSuperFrame.midX, y: transformedSuperFrame.midY), duration: 0.25, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        self.statusNodeContainer.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, timingFunction: CAMediaTimingFunctionName.easeIn.rawValue, removeOnCompletion: false)
    }
    
    // MARK: - Visual Quote
    
    private var isVisualQuoteEnabled: Bool {
        return self.context.sharedContext.immediateExperimentalUISettings.visualQuote
    }
    
    /// Regular photos only: no secret or paid media, no ads, no tiled local files.
    private var isVisualQuoteSupported: Bool {
        guard let message = self.message, !self.isSecret, message.adAttribute == nil, message.paidContent == nil, self.tilingNode == nil else {
            return false
        }
        return message.media.contains(where: { $0 is TelegramMediaImage })
    }
    
    override func contentLongTapAction(location: CGPoint) -> Bool {
        guard self.isVisualQuoteEnabled, self.isVisualQuoteSupported, let image = self.imageNode.image else {
            return false
        }
        let bounds = self.imageNode.bounds
        guard bounds.width > 0.0, bounds.height > 0.0 else {
            return false
        }
        let pointInImage = self.scrollNode.view.convert(location, to: self.imageNode.view)
        guard bounds.contains(pointInImage) else {
            return false
        }
        let normalizedPoint = CGPoint(x: pointInImage.x / bounds.width, y: pointInImage.y / bounds.height)
        
        // Show a default frame around the point right away; detection then pulls it onto the object if one is found.
        let defaultRegion = VisualQuoteDetector.pointRegion(at: normalizedPoint, imageSize: bounds.size)
        self.setVisualQuoteRegion(defaultRegion, animated: true)
        HapticFeedback().impact(.light)
        
        self.visualQuoteDetectionId += 1
        let detectionId = self.visualQuoteDetectionId
        VisualQuoteDetector.detect(image: image, normalizedPoint: normalizedPoint, completion: { [weak self] detection in
            guard let self, self.visualQuoteDetectionId == detectionId, self.visualQuoteFrameNode != nil else {
                return
            }
            if case let .object(region, _) = detection {
                self.setVisualQuoteRegion(region, animated: true)
                HapticFeedback().tap()
            }
        })
        return true
    }
    
    override func activateAsInitial() {
        super.activateAsInitial()
        guard let region = VisualQuoteRegion(mediaSubject: self.mediaSubject) else {
            return
        }
        // Wait for the transition from the bubble to settle, then zoom to the region and dim the rest.
        Queue.mainQueue().after(0.45) { [weak self] in
            self?.zoomToVisualQuote(region: region)
        }
    }
    
    private func zoomToVisualQuote(region: VisualQuoteRegion) {
        guard let (_, contentNode) = self.zoomableContent else {
            return
        }
        let contentBounds = contentNode.bounds
        guard contentBounds.width > 0.0, contentBounds.height > 0.0 else {
            return
        }
        let scrollView = self.scrollNode.view
        let regionRect = region.rect(in: contentBounds.size)
        // Leave room around the fragment and keep the aspect ratio of the screen.
        let padded = regionRect.insetBy(dx: -regionRect.width * 0.35, dy: -regionRect.height * 0.35)
        let viewSize = scrollView.bounds.size
        
        // The gallery's top buttons and bottom toolbar float over the photo; the fragment should end up between them.
        let gap: CGFloat = 8.0
        var controlsTop: CGFloat = 0.0
        var controlsBottom: CGFloat = 0.0
        if self.controlsVisibility() {
            controlsTop = self.visualQuoteNavigationBarHeight
            if self.footerContentNode.supernode != nil && !self.footerContentNode.bounds.isEmpty {
                let footerFrame = self.footerContentNode.view.convert(self.footerContentNode.bounds, to: self.view)
                controlsBottom = max(0.0, viewSize.height - footerFrame.minY)
            }
        }
        let freeTop = controlsTop > 0.0 ? controlsTop + gap : 0.0
        let freeBottom = viewSize.height - (controlsBottom > 0.0 ? controlsBottom + gap : 0.0)
        
        var scale = min(viewSize.width / max(1.0, padded.width), viewSize.height / max(1.0, padded.height))
        // A tall fragment is zoomed a little less so it fits between the controls.
        scale = min(scale, (freeBottom - freeTop) / max(1.0, regionRect.height))
        scale = min(scrollView.maximumZoomScale, max(scrollView.minimumZoomScale, scale))
        
        // Put the fragment as close to the middle as the photo allows, the way zoom(to:) does: near an
        // edge the view stops at the photo's border (D-028). Only if that leaves the fragment under the
        // top buttons or the bottom toolbar, shift the photo just enough to clear them; the missing room
        // becomes a content inset, which goes away once the user scrolls or zooms (D-029).
        let zoomedSize = CGSize(width: contentBounds.width * scale, height: contentBounds.height * scale)
        let originY = zoomedSize.height < viewSize.height ? (viewSize.height - zoomedSize.height) / 2.0 : 0.0
        var offset = CGPoint()
        if zoomedSize.width > viewSize.width {
            offset.x = max(0.0, min(zoomedSize.width - viewSize.width, regionRect.midX * scale - viewSize.width / 2.0))
        }
        if zoomedSize.height > viewSize.height {
            offset.y = max(0.0, min(zoomedSize.height - viewSize.height, regionRect.midY * scale - viewSize.height / 2.0))
        }
        let regionTop = originY + regionRect.minY * scale - offset.y
        let regionBottom = originY + regionRect.maxY * scale - offset.y
        if regionBottom - regionTop <= freeBottom - freeTop {
            if regionTop < freeTop {
                offset.y -= freeTop - regionTop
            } else if regionBottom > freeBottom {
                offset.y += regionBottom - freeBottom
            }
        }
        let inset = UIEdgeInsets(top: max(0.0, -offset.y), left: 0.0, bottom: max(0.0, offset.y - (zoomedSize.height - viewSize.height)), right: 0.0)
        self.visualQuoteControlsInset = inset == UIEdgeInsets() ? nil : inset
        UIView.animate(withDuration: 0.35, delay: 0.0, options: [.curveEaseInOut], animations: {
            scrollView.zoomScale = scale
            scrollView.contentInset = inset
            scrollView.contentOffset = offset
        })
        
        // Dim the photo around the quoted area and keep it that way: the highlight lives inside
        // the zoomable content, so it follows every zoom and scroll until the gallery closes.
        let highlight = VisualQuoteFrameNode(region: region, mode: .highlight)
        highlight.frame = contentBounds
        highlight.update(imageFrame: contentBounds, visibleBounds: contentBounds, region: region, animated: false)
        self.visualQuoteHighlightNode = highlight
        contentNode.addSubnode(highlight)
        self.updateVisualQuoteHighlightOutline()
        highlight.animateIn()
    }
    
    override func scrollViewDidZoom(_ scrollView: UIScrollView) {
        super.scrollViewDidZoom(scrollView)
        self.updateVisualQuoteHighlightOutline()
        self.updateVisualQuoteLayout(transition: .immediate)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if self.visualQuoteFrameNode != nil {
            self.updateVisualQuoteLayout(transition: .immediate)
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.clearVisualQuoteControlsInset()
    }
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        self.clearVisualQuoteControlsInset()
    }
    
    private func clearVisualQuoteControlsInset() {
        guard self.visualQuoteControlsInset != nil else {
            return
        }
        self.visualQuoteControlsInset = nil
        let scrollView = self.scrollNode.view
        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
            scrollView.contentInset = UIEdgeInsets()
        })
    }
    
    private func updateVisualQuoteHighlightOutline() {
        guard let highlight = self.visualQuoteHighlightNode, let (_, contentNode) = self.zoomableContent else {
            return
        }
        let onScreenWidth = self.visualQuoteImageFrame.width
        guard onScreenWidth > 0.0 else {
            return
        }
        highlight.setOutlineWidth(contentNode.bounds.width / onScreenWidth)
    }
    
    private func clearVisualQuoteHighlight() {
        guard let highlight = self.visualQuoteHighlightNode else {
            return
        }
        self.visualQuoteHighlightNode = nil
        highlight.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak highlight] _ in
            highlight?.removeFromSupernode()
        })
    }
    
    override func contentTapAction() -> Bool {
        if self.visualQuoteFrameNode != nil {
            self.clearVisualQuoteSelection(animated: true)
            return true
        }
        return false
    }
    
    override func contentDoubleTapAction(location: CGPoint) -> Bool {
        return self.visualQuoteFrameNode != nil
    }
    
    /// The photo's on-screen frame in this node's coordinates.
    private var visualQuoteImageFrame: CGRect {
        return self.imageNode.view.convert(self.imageNode.bounds, to: self.view)
    }
    
    private func setVisualQuoteRegion(_ region: VisualQuoteRegion, animated: Bool) {
        self.visualQuoteRegion = region
        let frameNode: VisualQuoteFrameNode
        var isNew = false
        if let current = self.visualQuoteFrameNode {
            frameNode = current
        } else {
            self.clearVisualQuoteHighlight()
            frameNode = VisualQuoteFrameNode(region: region)
            frameNode.isAccessibilityElement = true
            frameNode.accessibilityLabel = self.presentationData.strings.VisualQuote_VoiceOver_SelectedArea
            frameNode.regionChanged = { [weak self] region in
                guard let self else {
                    return
                }
                self.visualQuoteRegion = region
                self.updateVisualQuoteReplyButton(transition: .immediate)
            }
            frameNode.dragEnded = { [weak self] in
                self?.updateVisualQuoteReplyButton(transition: .animated(duration: 0.3, curve: .spring))
            }
            self.visualQuoteFrameNode = frameNode
            // Keep the overlay under the scroll view so its pinch recognizer sees touches
            // that start inside the selection. One finger edits; two fingers move the photo.
            self.scrollNode.addSubnode(frameNode)
            isNew = true
            self.visualQuotePreviousPanMinimumTouches = self.scrollNode.view.panGestureRecognizer.minimumNumberOfTouches
            self.scrollNode.view.panGestureRecognizer.minimumNumberOfTouches = 2
        }
        frameNode.frame = self.scrollNode.view.bounds
        frameNode.update(imageFrame: self.visualQuoteImageFrame, visibleBounds: self.bounds.insetBy(dx: 0.0, dy: 0.0), region: region, animated: animated && !isNew)
        if isNew && animated {
            frameNode.animateIn()
        }
        self.updateVisualQuoteReplyButton(transition: isNew ? .animated(duration: 0.2, curve: .easeInOut) : .animated(duration: 0.3, curve: .spring))
    }
    
    private func clearVisualQuoteSelection(animated: Bool) {
        self.visualQuoteDetectionId += 1
        self.visualQuoteRegion = nil
        if let frameNode = self.visualQuoteFrameNode {
            self.visualQuoteFrameNode = nil
            if let minimumTouches = self.visualQuotePreviousPanMinimumTouches {
                self.scrollNode.view.panGestureRecognizer.minimumNumberOfTouches = minimumTouches
                self.visualQuotePreviousPanMinimumTouches = nil
            }
            self.scrollNode.view.isScrollEnabled = !self.scrollNode.view.zoomScale.isEqual(to: self.scrollNode.view.minimumZoomScale)
            if animated {
                frameNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak frameNode] _ in
                    frameNode?.removeFromSupernode()
                })
            } else {
                frameNode.removeFromSupernode()
            }
        }
        self.updateVisualQuoteReplyButton(transition: animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate)
    }
    
    private func updateVisualQuoteLayout(transition: ContainedViewLayoutTransition) {
        if let frameNode = self.visualQuoteFrameNode, let region = self.visualQuoteRegion {
            frameNode.frame = self.scrollNode.view.bounds
            frameNode.update(imageFrame: self.visualQuoteImageFrame, visibleBounds: self.bounds, region: region, animated: false)
        }
        self.updateVisualQuoteReplyButton(transition: transition)
    }
    
    private func updateVisualQuoteReplyButton(transition: ContainedViewLayoutTransition) {
        guard let region = self.visualQuoteRegion, self.visualQuoteFrameNode != nil else {
            if let button = self.visualQuoteReplyButton {
                self.visualQuoteReplyButton = nil
                if transition.isAnimated {
                    button.layer.animateScale(from: 1.0, to: 0.8, duration: 0.2, removeOnCompletion: false)
                    button.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak button] _ in
                        button?.removeFromSupernode()
                    })
                } else {
                    button.removeFromSupernode()
                }
            }
            return
        }
        
        let button: VisualQuoteReplyButtonNode
        var isNew = false
        if let current = self.visualQuoteReplyButton {
            button = current
        } else {
            button = VisualQuoteReplyButtonNode()
            self.visualQuoteReplyButton = button
            self.addSubnode(button)
            isNew = true
        }
        let size = button.update(theme: defaultDarkColorPresentationTheme, title: self.presentationData.strings.Conversation_ContextMenuReply, action: { [weak self] in
            self?.visualQuoteReplyPressed()
        }, transition: transition)
        
        let imageFrame = self.visualQuoteImageFrame
        let regionRect = CGRect(x: imageFrame.minX + region.rect.minX * imageFrame.width, y: imageFrame.minY + region.rect.minY * imageFrame.height, width: region.rect.width * imageFrame.width, height: region.rect.height * imageFrame.height)
        let spacing: CGFloat = 20.0
        let topLimit: CGFloat = 90.0
        let bottomLimit: CGFloat = self.bounds.height - 110.0
        
        var frame = CGRect(origin: CGPoint(x: regionRect.midX - size.width / 2.0, y: regionRect.maxY + spacing), size: size)
        if frame.maxY > bottomLimit {
            frame.origin.y = regionRect.minY - spacing - size.height
            if frame.minY < topLimit {
                frame.origin.y = bottomLimit - size.height
            }
        }
        frame.origin.x = max(16.0, min(self.bounds.width - 16.0 - size.width, frame.origin.x))
        frame.origin.x = floor(frame.origin.x)
        frame.origin.y = floor(frame.origin.y)
        
        if isNew {
            button.frame = frame
            if transition.isAnimated {
                button.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                button.layer.animateSpring(from: 0.8 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.5)
            }
        } else {
            transition.updateFrame(node: button, frame: frame)
        }
    }
    
    private func visualQuoteReplyPressed() {
        guard let message = self.message, let region = self.visualQuoteRegion else {
            return
        }
        // Mirrors the "Reply" action of the "more" menu; the region rides along as the reply's inner subject.
        let context = self.context
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: message.id.peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self, let peer, canSendMessagesToPeer(peer), let navigationController = self.baseNavigationController() else {
                return
            }
            self.beginCustomDismiss(.simpleAnimation)
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil, subject: region.innerSubject), timecode: nil, setupReply: true)))
            Queue.mainQueue().after(0.3) {
                self.completeCustomDismiss(false)
            }
        })
    }
    
    override func visibilityUpdated(isVisible: Bool) {
        super.visibilityUpdated(isVisible: isVisible)
        
        /*if let (_, mediaReference) = self.contextAndMedia, let _ = mediaReference.concrete(TelegramMediaFile.self) {
            if isVisible {
            } else {
                self.fetchDisposable.set(nil)
            }
        }*/
    }
    
    override func title() -> Signal<String, NoError> {
        return self._title.get()
    }
    
    override func titleContent() -> Signal<GalleryTitleView.Content?, NoError> {
        return self._titleContent.get()
    }
    
    override func rightBarButtonItems() -> Signal<[UIBarButtonItem]?, NoError> {
        return self._rightBarButtonItems.get()
    }
    
    override func footerContent() -> Signal<(GalleryFooterContentNode?, GalleryOverlayContentNode?), NoError> {
        return .single((self.footerContentNode, self.recognitionOverlayContentNode))
    }
    
    @objc func statusPressed() {
        if let (_, mediaReference) = self.contextAndMedia, let status = self.status {
            var resource: MediaResourceReference?
            var statsCategory: MediaResourceStatsCategory?
            if let fileReference = mediaReference.concrete(TelegramMediaFile.self) {
                resource = fileReference.resourceReference(fileReference.media.resource)
                statsCategory = statsCategoryForFileWithAttributes(fileReference.media.attributes)
            } else if let imageReference = mediaReference.concrete(TelegramMediaImage.self ) {
                resource = (largestImageRepresentation(imageReference.media.representations)?.resource).flatMap(imageReference.resourceReference)
                statsCategory = .image
            }
            if let resource = resource {
                switch status {
                    case .Fetching:
                        self.context.engine.resources.cancelInteractiveResourceFetch(id: EngineMediaResource.Id(resource.resource.id))
                    case .Remote:
                    self.fetchDisposable.set(fetchedMediaResource(mediaBox: self.context.account.postbox.mediaBox, userLocation: (self.message?.id.peerId).flatMap(MediaResourceUserLocation.peer) ?? .other, userContentType: .image, reference: resource, statsCategory: statsCategory ?? .generic).start())
                    default:
                        break
                }
            }
        }
    }
    
    override func adjustForPreviewing() {
        super.adjustForPreviewing()
        
        self.recognitionOverlayContentNode.isHidden = true
    }
    
    private func canDelete() -> Bool {
        guard let message = self.message else {
            return false
        }
        var canDelete = false
        if let peer = message.peers[message.id.peerId] {
            if peer is TelegramUser || peer is TelegramSecretChat {
                canDelete = true
            } else if let _ = peer as? TelegramGroup {
                canDelete = true
            } else if let channel = peer as? TelegramChannel {
                if message.flags.contains(.Incoming) {
                    canDelete = channel.hasPermission(.deleteAllMessages)
                } else {
                    canDelete = true
                }
            } else {
                canDelete = false
            }
        } else {
            canDelete = false
        }
        if let _ = message.media.first(where: { $0 is TelegramMediaPoll }) {
            canDelete = false
        }
        return canDelete
    }
    
    override var keyShortcuts: [KeyShortcut] {
        let strings = self.presentationData.strings
        
        var keyShortcuts: [KeyShortcut] = []
        keyShortcuts.append(
            KeyShortcut(
                title: strings.KeyCommand_Share,
                input: "S",
                modifiers: [.command],
                action: { [weak self] in
                    self?.footerContentNode.actionButtonPressed()
                }
            )
        )
        if self.canDelete() {
            keyShortcuts.append(
                KeyShortcut(
                    input: "\u{8}",
                    modifiers: [],
                    action: { [weak self] in
                        self?.footerContentNode.deleteButtonPressed()
                    }
                )
            )
        }
        return keyShortcuts
    }
}

/*private func tileRectForImage(_ mappedImage: CGImage, rect: CGRect) -> CGRect {
    let scaleX = CGFloat(mappedImage.width) / lowResolutionImage.size.width
    let scaleY = CGFloat(mappedImage.height) / lowResolutionImage.size.height
    
    let mappedX = rect.minX * scaleX
    let mappedY = rect.minY * scaleY
    let mappedWidth = rect.width * scaleX
    let mappedHeight = rect.height * scaleY
    
    return CGRect(x: mappedX, y: mappedY, width: mappedWidth, height: mappedHeight)
}*/

private func zoomScale(for zoomLevel: CGFloat) -> CGFloat {
    return pow(2.0, zoomLevel - 1.0)
}

private func zoomLevel(for zoomScale: CGFloat) -> CGFloat {
    return log2(zoomScale) + 1.0
}

private final class TilingLayer: CATiledLayer {
    override var contentsScale: CGFloat {
        get {
            return super.contentsScale
        } set(value) {
            super.contentsScale = value
        }
    }
}

class TilingView: UIView {
    let image: CGImage
    let path: String
    var cachedScaledImage: UIImage?
    
    let imageSize: CGSize
    let tileSize: CGSize
    var normalizedSize: CGSize?
    
    override static var layerClass: AnyClass {
        return TilingLayer.self
    }
    
    private var tiledLayer: TilingLayer {
        return self.layer as! TilingLayer
    }
    
    init(image: CGImage, path: String) {
        self.image = image
        self.path = path
        
        self.tileSize = CGSize(width: 256.0, height: 256.0)
        self.imageSize = CGSize(width: image.width, height: image.height)
        
        super.init(frame: CGRect())
        
        self.tiledLayer.contentsScale = UIScreenScale
        let scale = self.tiledLayer.contentsScale
        self.tiledLayer.tileSize = CGSize(width: self.tileSize.width * scale, height: self.tileSize.height * scale)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        return self.imageSize
    }
    
    func setMaximumZoomScale(_ value: CGFloat, normalizedSize: CGSize) {
        if self.normalizedSize != normalizedSize {
            self.normalizedSize = normalizedSize
            
            /*let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: Int(max(self.imageSize.width / 4.0, self.imageSize.height / 4.0))
            ]

            let startTime = CACurrentMediaTime()
            if let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: self.path) as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                self.cachedScaledImage = UIImage(cgImage: image)
            }
            print("create thumbnail: \((CACurrentMediaTime() - startTime) * 1000.0) ms")*/
        }
        
        let levels = max(1, Int(zoomLevel(for: value)))
        self.tiledLayer.levelsOfDetail = levels
        self.tiledLayer.levelsOfDetailBias = levels - 1
    }
    
    override func draw(_ rect: CGRect) {
        guard let normalizedSize = self.normalizedSize else {
            return
        }
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        let image = self.image
        let cachedScaledImage = self.cachedScaledImage
        let imageSize = self.imageSize
        context.setBlendMode(.copy)
        
        let contentScale = context.ctm.a
        let normalizedContentScale = contentScale / UIScreenScale
        
        let normalizedRect = rect
        
        let normalizationScale = imageSize.width / normalizedSize.width
        
        let normalizedCroppingRect = CGRect(origin: CGPoint(x: normalizedRect.minX * normalizationScale, y: normalizedRect.minY * normalizationScale), size: CGSize(width: normalizedRect.width * normalizationScale, height: normalizedRect.height * normalizationScale))
        
        let tileSizes: [CGFloat] = [
            //8192.0,
            //4096.0,
            2048.0,
            1024.0,
            512.0,
            256.0
        ]
        
        var maximumTileSize: CGFloat = tileSizes[0]
        for i in (0 ..< tileSizes.count).reversed() {
            if tileSizes[i] > normalizedCroppingRect.width {
                break
            }
            maximumTileSize = tileSizes[i]
        }
        
        let xMinTile = Int(floor(normalizedCroppingRect.minX / maximumTileSize))
        let xMaxTile = Int(ceil(normalizedCroppingRect.maxX / maximumTileSize))
        let yMinTile = Int(floor(normalizedCroppingRect.minY / maximumTileSize))
        let yMaxTile = Int(ceil(normalizedCroppingRect.maxY / maximumTileSize))
        
        for y in yMinTile ... yMaxTile {
            let imageMinY = floor(CGFloat(y) * maximumTileSize)
            var imageMaxY = ceil(CGFloat(y + 1) * maximumTileSize)
            imageMaxY = min(imageMaxY, imageSize.height)
            if imageMaxY <= imageMinY {
                continue
            }
            
            for x in xMinTile ... xMaxTile {
                let imageMinX = floor(CGFloat(x) * maximumTileSize)
                var imageMaxX = ceil(CGFloat(x + 1) * maximumTileSize)
                imageMaxX = min(imageMaxX, imageSize.width)
                if imageMaxX <= imageMinX {
                    continue
                }
                
                let imageRect = CGRect(origin: CGPoint(x: imageMinX, y: imageMinY), size: CGSize(width: imageMaxX - imageMinX, height: imageMaxY - imageMinY))
                
                let drawingRect = CGRect(origin: CGPoint(x: imageRect.minX / normalizationScale, y: imageRect.minY / normalizationScale), size: CGSize(width: imageRect.width / normalizationScale, height: imageRect.height / normalizationScale))
                
                var tileImage: CGImage?
                if normalizedContentScale < 1.1, let cachedScaledImage = cachedScaledImage {
                    let cachedScale = cachedScaledImage.size.width / self.imageSize.width
                    let scaledImageRect = CGRect(origin: CGPoint(x: imageRect.minX * cachedScale, y: imageRect.minY * cachedScale), size: CGSize(width: imageRect.width * cachedScale, height: imageRect.height * cachedScale))
                    tileImage = cachedScaledImage.cgImage!.cropping(to: scaledImageRect)
                } else {
                    tileImage = image.cropping(to: imageRect)
                }
                
                if let tileImage = tileImage {
                    var scaledSide = max(imageRect.width, imageRect.height)
                    let targetSide = max(drawingRect.width, drawingRect.height)
                    while true {
                        let maybeSide = round(scaledSide * 0.5)
                        if maybeSide < targetSide {
                            break
                        } else {
                            scaledSide = maybeSide
                        }
                    }
                    
                    /*let scaledSize = imageRect.size.fitted(CGSize(width: scaledSide, height: scaledSide))
                    let scaledImage = generateImage(scaledSize, contextGenerator: { size, scaledContext in
                        scaledContext.setBlendMode(.copy)
                        let startTime = CACurrentMediaTime()
                        scaledContext.draw(tileImage, in: CGRect(origin: CGPoint(), size: size))
                        print("draw scaled: \((CACurrentMediaTime() - startTime) * 1000.0) ms")
                    }, opaque: true, scale: UIScreenScale)
                    
                    if let scaledImage = scaledImage {
                        scaledImage.draw(in: drawingRect.insetBy(dx: -0.5, dy: -0.5), blendMode: .copy, alpha: 1.0)
                    }*/
                    
                    let startTime = CACurrentMediaTime()
                    context.translateBy(x: drawingRect.midX, y: drawingRect.midY)
                    context.scaleBy(x: 1.0, y: -1.0)
                    context.translateBy(x: -drawingRect.midX, y: -drawingRect.midY)
                    context.draw(tileImage, in: drawingRect.insetBy(dx: -0.5, dy: -0.5))
                    context.translateBy(x: drawingRect.midX, y: drawingRect.midY)
                    context.scaleBy(x: 1.0, y: -1.0)
                    context.translateBy(x: -drawingRect.midX, y: -drawingRect.midY)
                    print("draw direct: \((CACurrentMediaTime() - startTime) * 1000.0) ms")
                }
            }
        }
    }
    
    private func annotate(rect: CGRect, col: Int, row: Int, zoomLevel: CGFloat, scale: CGFloat, context: CGContext) {
        let lineWidth = 2.0 / scale
        let halfLineWidth = lineWidth / 2.0
        //let fontSize = 12.0 / scale
        
        //NSString *pointString = [NSString stringWithFormat:@"%@x(%@, %@) @%@x", @(zoomLevel), @(col), @(row), @([UIScreen mainScreen].scale)];
        //CGPoint textOrigin = CGPointMake(CGRectGetMinX(rect) + lineWidth, CGRectGetMinY(rect) + lineWidth);
        /*[pointString drawAtPoint:textOrigin withAttributes:@{
                                                             NSFontAttributeName: [UIFont boldSystemFontOfSize:fontSize],
                                                             NSForegroundColorAttributeName: [UIColor darkGrayColor]
                                                             }];*/
        context.setFillColor(UIColor.red.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect.insetBy(dx: halfLineWidth, dy: halfLineWidth))
    }
}

private final class TilingNode: ASDisplayNode {
    init(image: CGImage, path: String) {
        super.init()
        
        self.setViewBlock {
            return TilingView(image: image, path: path)
        }
    }
}

extension UIBezierPath {
    convenience init(rect: RecognizedContent.Rect, radius r: CGFloat) {
        let left  = CGFloat.pi
        let up    = CGFloat.pi * 1.5
        let down  = CGFloat.pi * 0.5
        let right = CGFloat.pi * 0.0
        
        self.init()
        
        addArc(withCenter: CGPoint(x: rect.topLeft.x + r, y: rect.topLeft.y + r), radius: r, startAngle: left, endAngle: up, clockwise: true)
        addArc(withCenter: CGPoint(x: rect.topRight.x - r, y: rect.topRight.y + r), radius: r, startAngle: up, endAngle: right, clockwise: true)
        addArc(withCenter: CGPoint(x: rect.bottomRight.x - r, y: rect.bottomRight.y - r), radius: r, startAngle: right, endAngle: down, clockwise: true)
        addArc(withCenter: CGPoint(x: rect.bottomLeft.x + r, y: rect.bottomLeft.y - r), radius: r, startAngle: down, endAngle: left, clockwise: true)
        close()
    }
}

private func generateMaskImage(size: CGSize, recognitions: [RecognizedContent]) -> UIImage? {
    return generateImage(size, opaque: false, scale: 1.0, rotatedContext: { size, c in
        let bounds = CGRect(origin: CGPoint(), size: size)
        c.clear(bounds)
        
        c.setFillColor(UIColor(rgb: 0x000000, alpha: 0.4).cgColor)
        c.fill(bounds)
        
        c.setBlendMode(.clear)
        for recognition in recognitions {
            let mappedRect = recognition.rect.convertTo(size: size, insets: UIEdgeInsets(top: -4.0, left: -2.0, bottom: -4.0, right: -2.0))
            let path = UIBezierPath(rect: mappedRect, radius: 3.5)
            c.addPath(path.cgPath)
            c.fillPath()
        }
    })
}

private class RecognizedContentContainer: ASDisplayNode {
    private let size: CGSize
    private let recognitions: [RecognizedContent]
    
    private let maskNode: ASImageNode
    private var selectionNode: RecognizedTextSelectionNode?
    
    var barcodeAction: ((String, CGRect) -> Void)?
    
    init(size: CGSize, recognitions: [RecognizedContent], presentationData: PresentationData, present: @escaping (ViewController, Any?) -> Void, performAction: @escaping (String, RecognizedTextSelectionAction) -> Void) {
        self.size = size
        self.recognitions = recognitions
        
        self.maskNode = ASImageNode()
        self.maskNode.image = generateMaskImage(size: size, recognitions: recognitions)
                
        super.init()
        
        let selectionNode = RecognizedTextSelectionNode(size: size, theme: RecognizedTextSelectionTheme(selection: presentationData.theme.chat.message.incoming.textSelectionColor, knob:  presentationData.theme.chat.message.incoming.textSelectionKnobColor, knobDiameter: 12.0), strings: presentationData.strings, recognitions: recognitions, updateIsActive: { _ in }, present: present, rootNode: self, performAction: { string, action in
            performAction(string, action)
        })
        self.selectionNode = selectionNode
        
        self.addSubnode(self.maskNode)
        self.addSubnode(selectionNode.highlightAreaNode)
        self.addSubnode(selectionNode)
    }
    
    func dismissSelection() {
        let _ = self.selectionNode?.dismissSelection()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:))))
    }
    
    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let location = gestureRecognizer.location(in: self.view)
        
        for recognition in self.recognitions {
            let mappedRect = recognition.rect.convertTo(size: self.bounds.size)
            if mappedRect.boundingFrame.contains(location) {
                if case let .qrCode(payload) = recognition.content {
                    self.barcodeAction?(payload, mappedRect.boundingFrame)
                }
                break
            }
        }
    }
    
    func update(size: CGSize, transition: ContainedViewLayoutTransition) {
        let bounds = CGRect(origin: CGPoint(), size: size)
        transition.updateFrame(node: self.maskNode, frame: bounds)
        if let selectionNode = self.selectionNode {
            transition.updateFrame(node: selectionNode, frame: bounds)
            selectionNode.highlightAreaNode.frame = bounds
        }
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for recognition in self.recognitions {
            let mappedRect = recognition.rect.convertTo(size: self.bounds.size)
            if mappedRect.boundingFrame.insetBy(dx: -20.0, dy: -20.0).contains(point) {
                return true
            }
        }
        
        if (self.selectionNode?.dismissSelection() ?? false) {
            return true
        }

        return false
    }
}


private class ImageRecognitionOverlayContentNode: GalleryOverlayContentNode {
    private let backgroundContainer: GlassBackgroundContainerView
    private let backgroundView: GlassBackgroundView
    private let iconView: UIImageView
    
    var action: ((Bool) -> Void)?
    private var appeared = false
    
    private var validLayout: (CGSize, LayoutMetrics, UIEdgeInsets)?
    private var interfaceIsHidden: Bool = false
    
    var isSelected: Bool = false
    
    init(theme: PresentationTheme) {
        self.backgroundContainer = GlassBackgroundContainerView()
        self.backgroundView = GlassBackgroundView()
        self.iconView = UIImageView()
        
        self.iconView.image = generateTintedImage(image: UIImage(bundleImageName: "Media Gallery/LiveTextIcon"), color: .white)?.withRenderingMode(.alwaysTemplate)
        self.iconView.contentMode = .center
        
        super.init()
        
        self.backgroundContainer.contentView.addSubview(self.backgroundView)
        self.backgroundView.contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.onTapGesture(_:))))
        
        self.view.addSubview(self.backgroundContainer)
        self.backgroundView.contentView.addSubview(self.iconView)
    }
    
    @objc private func onTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            let newValue = !self.isSelected
            self.isSelected = newValue
            
            if !newValue && !self.interfaceIsHidden, let (size, metrics, insets) = self.validLayout {
                self.updateLayout(size: size, metrics: metrics, insets: insets, isHidden: self.interfaceIsHidden, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
            
            self.action?(newValue)
            
            if self.interfaceIsHidden && !newValue {
                let transition = ComponentTransition.easeInOut(duration: 0.2)
                transition.setAlpha(view: self.backgroundContainer, alpha: 0.0)
            }
        }
    }
    
    func transitionIn() {
        guard self.backgroundContainer.alpha.isZero else {
            return
        }
        self.appeared = true
        if self.isSelected {
            ComponentTransition.easeInOut(duration: 0.2).setAlpha(view: self.backgroundContainer, alpha: 1.0)
        }
    }
    
    override func updateLayout(size: CGSize, metrics: LayoutMetrics, insets: UIEdgeInsets, isHidden: Bool, transition: ContainedViewLayoutTransition) {
        let transition = ComponentTransition(transition)
        
        self.validLayout = (size, metrics, insets)
        
        self.interfaceIsHidden = isHidden
        
        let buttonSize = CGSize(width: 44.0, height: 44.0)
        
        self.backgroundContainer.update(size: buttonSize, isDark: true, transition: transition)
        
        self.backgroundView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: buttonSize)
        let tintColor: GlassBackgroundView.TintColor = .init(kind: .custom(style: .default, color: UIColor(white: 1.0, alpha: 1.0)))
        self.backgroundView.update(size: buttonSize, cornerRadius: buttonSize.height * 0.5, isDark: true, tintColor: tintColor, isInteractive: true, transition: transition)
        
        self.iconView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: buttonSize)
        transition.setTintColor(view: self.iconView, color: .black)
        
        if self.appeared {
            if !self.isSelected && isHidden {
                transition.setAlpha(view: self.backgroundContainer, alpha: 0.0)
            } else {
                transition.setAlpha(view: self.backgroundContainer, alpha: self.isSelected ? 1.0 : 0.0)
            }
        } else {
            transition.setAlpha(view: self.backgroundContainer, alpha: 0.0)
        }
        
        var buttonPosition: CGPoint
        buttonPosition = CGPoint(x: size.width - insets.right - buttonSize.width - 16.0, y: insets.top - 50.0)
        
        transition.setFrame(view: self.backgroundContainer, frame: CGRect(origin: buttonPosition, size: buttonSize))
    }
    
    override func animateIn(previousContentNode: GalleryOverlayContentNode?, transition: ContainedViewLayoutTransition) {
        guard self.appeared && (!self.interfaceIsHidden || self.isSelected) else {
            return
        }
        if let previousContentNode = previousContentNode as? ImageRecognitionOverlayContentNode, previousContentNode.appeared {
            self.backgroundContainer.alpha = 1.0
        } else {
            self.backgroundContainer.alpha = 0.0
            if self.isSelected {
                ComponentTransition.easeInOut(duration: 0.2).setAlpha(view: self.backgroundContainer, alpha: 1.0)
            }
        }
    }
    
    override func animateOut(nextContentNode: GalleryOverlayContentNode?, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        ComponentTransition.easeInOut(duration: 0.2).setAlpha(view: self.backgroundContainer, alpha: 0.0)
        completion()
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if self.backgroundContainer.alpha > 0.0 && self.backgroundContainer.frame.contains(point) {
            return true
        } else {
            return false
        }
    }
}
