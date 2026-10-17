# Visual Quote — code map (M1)

> **Snapshot from M1, written before implementation.** The options in section 5 and the open questions in section 7 have since been decided; later decisions are in [decisions.md](decisions.md), and the final state of the code is in [README.md](README.md).

The result of stage M1: how the relevant parts of Telegram-iOS work and where Visual Quote plugs in. No code was changed. Paths are relative to the repository root; `file:line` refers to commit `f1dd7a2dbd` (master as of 2026-10-12). Facts were checked by reading the code; experiments are marked with the word "checked".

## 0. The main finding: "reply to part of a message" already exists

A reply in Telegram-iOS has the notion of an **inner subject**, `EngineMessageReplyInnerSubject` (`submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift:12`): currently `.todoItem(Int32)` (a to-do list item) and `.pollOption(Data)` (a poll option). This mechanism covers the whole path Visual Quote needs:

| Step | Where | What it does with innerSubject |
| --- | --- | --- |
| Composer state | `ReplyMessageAttribute.innerSubject` (`submodules/TelegramCore/Sources/SyncCore/SyncCore_ReplyMessageAttribute.swift`) | stored next to `quote` |
| Reply panel above the input field | `ReplyAccessoryPanelNode.swift:275-318` | shows the text of the item/option instead of the message text |
| Sending | `PendingMessageManager.swift:1240-1243` → `Api.InputReplyTo.inputReplyToMessage(... todoItemId, pollOption)` (`submodules/TelegramApi/Sources/Api13.swift:352`) | goes to the server in the `todo_item_id:int` / `poll_option:bytes` fields |
| Receiving | `Api.MessageReplyHeader` with the same fields (`Api18.swift:541`) → `ReplyMessageAttribute.innerSubject` | |
| Bubble header | `ChatMessageReplyInfoNode.swift:450-460, 531` | finds the option/item in the original message's media and draws its text and media |
| Tap to navigate | `ChatMessageBubbleItemNode.swift:5990` → `navigateToMessage(... subject: attribute.innerSubject)`; `getInnerReplySubjectRect(innerSubject:)` `:7655` | highlights exactly that item/option inside the message |
| From the gallery | `ChatImageGalleryItem.swift:787-804` | "Reply" in the "more" menu already passes `innerSubject` through `ChatControllerSubject.MessageHighlight(quote:subject:)` (`submodules/AccountContext/Sources/ChatController.swift:908`) |

Conclusion: Visual Quote is a new case of `innerSubject`, something like `.imageRegion(...)`. Locally (composer, panel, bubble, navigation, gallery) everything maps onto existing points. The only gap is the **wire format**: `inputReplyToMessage` has no field for an image region; in production it would be a field next to `todo_item_id` / `poll_option` (see section 5).

## 1. Photo viewer (gallery)

**Opening chain.** Tap on a photo in a bubble: `ChatMessageInteractiveMediaNode.swift:668, 743, 779-792` → `ChatMessageMediaBubbleContentNode.swift:47-71` (`openMessage`) → `ChatController.swift:872, 1484-1749` (`OpenChatMessageParams`, `transitionNode`, `GalleryControllerActionInteraction`) → `OpenChatMessage.swift:32, 134, 371-409` → `GalleryController` (`submodules/GalleryUI/Sources/GalleryController.swift:707`, init `:783`) → `GalleryControllerNode.swift:12` → `GalleryPagerNode.swift:82` → `ChatImageGalleryItem.swift:120`, node `ChatImageGalleryItemNode: ZoomableContentGalleryItemNode` `:220`.

**Where the image is.** `ZoomableContentGalleryItemNode.scrollNode: ASScrollNode` (`ZoomableContentGalleryItemNode.swift:7`), content `zoomableContent: (CGSize, ASDisplayNode)?` `:14`; for a photo this is `imageNode: TransformImageNode` (`ChatImageGalleryItem.swift:232`, assigned at `:523`), with the decoded `UIImage` in `TransformImageNode.image` (`submodules/Display/Source/TransformImageNode.swift:26`). Local files may use a `tilingNode` (`:242, :569-573`).

**Gestures already taken** (`ZoomableContentGalleryItemNode.swift:44-106`):
- one `TapLongTapOrDoubleTapGestureRecognizer` on `scrollNode.view`: a tap within 44pt of the edges is a single tap, otherwise it waits for a double tap; a single tap hides/shows the chrome, a double tap zooms with `scrollNode.view.zoom(to:)` / `setZoomScale` (`:100-102`);
- **a long press on the photo is recognized but not used**: the recognizer sends `.longTap` after 0.3 s (`submodules/Display/Source/TapLongTapOrDoubleTapGestureRecognizer.swift:228`, property `longTap` `:95`), and `contentTap` ignores it (`default: break`, `:104-105`);
- pinch and pan while zoomed are built into `UIScrollView` (`:200-248, :273-281`); swiping between photos is `GalleryPagerNode` paging (`:149-173`); a tap at the edge to turn the page is a second recognizer on the pager (`:193-363`); swipe down to close goes through the gallery's vertical `scrollView` (`GalleryControllerNode.swift:369, :561-630`);
- in Live Text mode: `RecognizedContentContainer` (`ChatImageGalleryItem.swift:1586`) and `RecognizedTextSelectionNode` with its own 0.3 s long press (`RecognizedTextSelectionNode.swift:293, :371`); active only after text recognition is turned on.

**Coordinates.** The content node sits at `(0,0,contentSize)` with an identity transform; zoom is the scroll view's transform (`:150-188`). Touch point → `scrollNode.view.convert(location, to: contentView)` (`:88`); dividing by `contentNode.bounds.size` gives a normalized 0…1 point. A ready precedent for normalized rectangles is recognized text: `recognition.rect.convertTo(size:)` (`ChatImageGalleryItem.swift:1593, :1614`; `ImageContentAnalysis.swift:132`), with an overlay container the size of `imageNode.bounds` (`:376, :445`).

**Bottom of the gallery.** `ChatItemGalleryFooterContentNode` (`submodules/GalleryUI/Sources/ChatItemGalleryFooterContentNode.swift`): buttons are assembled in `updateLayout` `:1178` as `GlassControlGroupComponent.Item(id:, content: .icon(...), action:)` in left/center/right groups `:1334-1443` (share / pip, settings, edit, textRecognition, stickers, fullscreen / delete), rendered by `GlassControlPanelComponent` with the `defaultDarkColorPresentationTheme` theme `:1450-1476`. The gallery theme is always dark: `GalleryController.swift:1185`.

**Reply already exists, but in the "more" menu** (`ChatImageGalleryItem.swift:787-804`, string `Conversation_ContextMenuReply`): `beginCustomDismiss(.simpleAnimation)` → `navigateToChatController(... subject: .message(id:, highlight: MessageHighlight(quote: nil, subject: innerSubject), timecode: nil, setupReply: true))` → after 0.3 s `completeCustomDismiss(false)`. This is the template for the "Reply" button after a selection.

**Closing and talking back to the chat.** `GalleryController.dismiss(forceAway:)` `:1486`, `GalleryItemNode.beginCustomDismiss/completeCustomDismiss` (`GalleryItemNode.swift:32-34`), `actionInteraction.updateCanReadHistory` on every close; there is no separate "gallery closed" callback. Gallery items reach the chat through `baseNavigationController()` / `galleryController()` (`GalleryItemNode.swift:35-36`) and `GalleryControllerActionInteraction` (`submodules/AccountContext/Sources/GalleryController.swift:26-66`, implementation `ChatController.swift:1607-1726`).

**Opening zoomed to a region.** There is no dedicated API; the only zoom calls are in the double-tap handler (`scrollNode.view.zoom(to:animated:)`). `scrollNode` is public, and `activateAsInitial()` (`GalleryItemNode.swift:88`) is an empty hook the controller calls for the initial item. Important: `resetScrollViewContents` resets the zoom when content is set and when the size changes (`:14-26, :115-133`), so zooming has to happen after the content and the layout are in place.


## 2. The full path of a text quote (the template to copy)

| Stage | Where | Details |
| --- | --- | --- |
| Selection | `submodules/TextSelectionNode/Sources/TextSelectionNode.swift:215, 284, 735-785` | the `.quote(range:)` action in the selection menu; string `Conversation_ContextMenuQuote`. The selection node is created when the message is "lifted" into the context menu: `ChatMessageTextBubbleContentNode.swift:1598-1628`, `enableQuote` conditions `:1653-1674` (there is text, the user can write, not a secret chat) |
| Handling | `ChatController.swift:4427`, `.quote` branch `:4565-4609` | takes the substring, cuts it at `quote_length_max` (1024, `SyncCore_TextEntitiesMessageAttribute.swift:443`), builds `EngineMessageReplyQuote(text:offset:entities:media:)` and puts it into `ChatInterfaceState.ReplyMessageSubject(messageId:quote:innerSubject:)`, then `withUpdatedReplyMessageSubject` and focus in the input field |
| Composer state | `submodules/ChatInterfaceState/Sources/ChatInterfaceState.swift:480-497, 515, 856` | `ReplyMessageSubject` mirrors `EngineMessageReplySubject` (`EnqueueMessage.swift:117-127`); saved to the draft, including the cloud draft (`:555, :679, :741`) |
| Panel above the input field | `submodules/TelegramUI/Components/Chat/ChatInputMessageAccessoryPanel/Sources/ChatInputMessageAccessoryPanel.swift` | the active component: `Contents.Reply { id, quote, innerSubject, message }` `:108-126`; height 52 `:427`; a 2pt bar in `inputPanel.panelControlAccentColor` `:416-433`; a 44×44 glass close button `:435-443`; title `Chat_ReplyPanel_ReplyToQuoteBy` in `Font.medium(14)` `:595-637`; the quote text on one line in `Font.regular(14)` `:664-667`; **the 35×35 thumbnail code is commented out** `:489-510`. Wiring: `ChatInterfaceStateAccessoryPanels.swift:23, 207-239` (tap → `presentReplyOptions`, long press → go to the message, cross → `setupReplyMessage(nil)`). The old `ReplyAccessoryPanelNode` is disabled (`:269-271`) but contains templates for the quote icon and the thumbnail |
| Editing the quote | `submodules/TelegramUI/Sources/Chat/ChatMessageActionOptions.swift:86, 359-579, 581-629` | a preview menu with an embedded `ChatControllerImpl` in `.standard(.previewing)` mode; items "Quote Selected Part / Select Specific Quote / Remove Quote" |
| Sending | `ChatControllerNode.swift:5024, 5171-5212` (checks that the quote is still in the text, otherwise the `Chat_ErrorQuoteOutdated*` alert), `EnqueueMessage.swift:130, 1015-1037` (`ReplyMessageAttribute(... isQuote: quote != nil, innerSubject)`), `PendingMessageManager.swift:1465-1501, 1880-1912` | `inputReplyToMessage` flags: 1<<2 `quoteText`, 1<<3 `quoteEntities`, 1<<4 `quoteOffset`, 1<<6 `todoItemId`, 1<<7 `pollOption`. The client does not handle `QUOTE_*` server errors |
| Receiving | `StoreMessage_Telegram.swift:542-563, 1138-1200` | `isQuote` = flag 1<<9; the quote is built if there is `quoteText` or `replyMedia`; plus `QuotedReplyMessageAttribute` with `replyFrom` |
| Bubble header | `ChatMessageBubbleItemNode.swift:2149-2171, 3030-3046` → `ChatMessageReplyInfoNode.swift` | the quote icon `Chat/Message/ReplyQuoteIcon` top right `:27-29, 928-946`; font `floor(baseDisplaySize * 14/17)`, title `Font.semibold`, text `Font.regular` `:195-197`; author colours `:229-268`; background and bar `MessageInlineBlockBackgroundView` `:897-926`; **the photo thumbnail in a reply: `imageSide = titleLineHeight * 2.0`** `:684-686`, corner radius 4, origin (9, 4) `:797`, text inset `floor(baseDisplaySize * 32/17)` `:629-632`; for a quote, the title takes up to 2 lines and the text up to 5 (50 when expanded) `:646-664` |
| Tap to navigate | `ChatMessageBubbleItemNode.swift:5960-5991` → `navigateToMessage(... NavigateToMessageParams(quote:subject:))` → `ChatControllerNavigateToMessage.swift:367-376` → `ChatHistoryListNode.scrollToMessage` `:3878` | centring on `getQuoteRect` (`PreparedChatHistoryViewTransition.swift:223-229`, `ChatMessageBubbleItemNode.swift:7634`); after scrolling, `ChatInterfaceHighlightedState(quote:subject:)` (`ChatControllerLoadDisplayNode.swift:5454-5476`), the `Chat_ToastQuoteNotFound` toast, the highlight is removed after 1.5 s; drawing: `updateHighlightedState` `:6960-7070` highlights the whole bubble with `authorNameColor.withMultipliedAlpha(0.2)`, and after 0.3 s it shrinks to the quote rectangle with a 0.4 s spring |
| Strings | `Telegram/Telegram-iOS/en.lproj/Localizable.strings:10166-10257` | `Conversation.ContextMenuQuote`, `Chat.ReplyPanel.ReplyToQuoteBy`, `Chat.ToastQuoteNotFound`, `Conversation.MessageOptionsQuote*` and others |

A reply to a photo without a quote already shows an `imageSide` thumbnail (≈2 line heights) in the header; this is what Visual Quote has to make "noticeably larger" (section 2.8 of the brief, variants at M4).

## 3. Theme, strings, flags

**Theme.** `PresentationTheme` (`submodules/TelegramPresentationData/Sources/PresentationTheme.swift:1576`), obtained from `context.sharedContext.currentPresentationData.with { $0 }` or the `presentationData` signal (`submodules/AccountContext/Sources/AccountContext.swift:1415-1416`). For bubbles: `theme.chat.message.incoming/outgoing` (`PresentationThemePartedColors` `:959`: `accentTextColor` `:967`, `accentControlColor` `:968`, `linkTextColor`, `bubble`); the reply panel is coloured with `theme.chat.inputPanel.panelControlAccentColor` (`ReplyAccessoryPanelNode.swift:76, 262-286, 414`). The sender's colour for the bar and name: `context.peerNameColors.get(nameColor, dark:)`; the canonical code is in `ChatMessageReplyInfoNode.swift:229-265` (incoming: a preset or `incoming.accentTextColor`; outgoing: always `outgoing.accentTextColor`). Gallery: `defaultDarkColorPresentationTheme` (`DefaultDarkPresentationTheme.swift:7`). Glass style: `GlassBackgroundView.useCustomGlassImpl` (`GlassBackgroundComponent.swift:501`), flags `fakeGlass`/`forceClearGlass`.

**Strings.** The source is `Telegram/Telegram-iOS/en.lproj/Localizable.strings`; the generator is `build-system/GenerateStrings/GenerateStrings.py` through the `GeneratedPresentationStrings` genrule (`Telegram/BUILD:149-164`). A key `A.B.C` becomes `strings.A_B_C`; values with `%@` become functions; the `_0/_1/_any` suffixes are pluralization. Adding a string to the English file is enough; there is no registration. Other languages are empty stubs (`Telegram/BUILD:192-198`), and a missing translation falls back to the English one from the bundle (`GenerateStrings.py:448-480`). This closes risk 5 of the brief: new strings show up in English, which is enough for the demo.

**Flag in Debug Settings.** `ExperimentalUISettings` (`submodules/TelegramUIPreferences/Sources/ExperimentalUISettings.swift`): a field, a value in `defaultSettings` (`:84`), an init parameter, decode (`:249`, template `decodeIfPresent(Bool.self, forKey:) ?? false` `:299`), encode (`:356`). The switch: `DebugController.swift`, an enum case (template `.keepChatNavigationStack`), `ItemListSwitchItem(... systemStyle: .glass ...)` and a write through `updateExperimentalUISettingsInteractively` (`:1054-1060`), added to the list at `:1872` (inside `if isMainApp`). Reading: `context.sharedContext.immediateExperimentalUISettings.<flag>` (`AccountContext.swift:1421`; example `ChatTextInputPanelNode.swift:816`). How to open Debug Settings in a signed-in app: 10 quick taps on the Settings tab icon (`TabBarController.swift:165-178` → `TelegramRootController.swift:229-234`); on the phone number screen, 10 taps on the title.

**Accessibility and haptics.** `accessibilityLabel` is set directly from strings (`ReplyAccessoryPanelNode.swift:60, 326-332`). `HapticFeedback` (`submodules/Display/Source/HapticFeedback.swift:128`): `tap()`, `impact(.light/.medium/...)`, `success()`; in the chat either `HapticFeedback().impact()` or a stored instance.

## 4. Vision: where to plug it in and whether it works in the simulator

**In the codebase** Vision is used with a plain `import Vision`; it is not declared in any BUILD file (only `weak_sdk_frameworks` in `submodules/LegacyComponents/BUILD:52-53`). The main precedent is object cutout for stickers:

- `submodules/TelegramUI/Components/MediaEditor/ImageObjectSeparation/Sources/ImageObjectSeparation.swift`: `cutoutImage(from:editedImage:crop:target:)` `:229` with `CutoutTarget.point(CGPoint?) / .index / .all` `:204-207`; the touch point is matched to an instance by the pixel label of `instanceMask` `:364-381`; the result is a `CutoutResult` with `extractedImage`, `edgesMaskImage`, `maskImage` (the mask is smoothed by `refineEdges` `:211`: blur → contrast → sharpen). On iOS 17+ it uses `VNGenerateForegroundInstanceMaskRequest`; **in the simulator it is forced (`forceCoreMLVariant`, `:23-29`) to switch to the CoreML model `u2netp`**, which it downloads from the `@stickersbackgroundseparation` channel (`:36-60`), so a signed-in account and network are needed; availability is `cutoutAvailability(context:)` `:35`.
- Call sites: `MediaEditor.swift:931-959`, `MediaCutoutScreen.swift:122, 431`, `DrawingScreen.swift:3193` ("Cut Out"), `MediaPickerScreen.swift:2410` (prefetch).
- **A ready glowing outline**: `StickerCutoutOutlineView` (`submodules/TelegramUI/Components/MediaEditorScreen/Sources/StickerCutoutOutlineView.swift:9`): mask → contour (`CIMorphologyMaximum` r=3, 256px raster, boundary tracing, Douglas–Peucker simplification) → `UIBezierPath`; layers: a `CAShapeLayer` with a white shadow (opacity 0.35, radius 4 `:22`), two `CAEmitterLayer`s (particles along the contour and a glow), `animateBump` 1→1.07→1 over 0.4 s `:127`. This is the closest "Telegram language" for highlighting a selection; Visual Quote needs a calm version of it without particles.
- Other: `VNClassifyImageRequest` (`ImageObjectClassification.swift:25-27`), `VNDetectFaceRectanglesRequest` + `VNGeneratePersonSegmentationRequest` (`MediaEditor.swift:2357-2385`), `VNRecognizeTextRequest`/`VNDetectBarcodesRequest` in `submodules/ImageContentAnalysis` (Live Text in the gallery, `ChatImageGalleryItem.swift:371`).

Refined conclusion on risk 2 in light of this: an object outline in the simulator **is possible through the existing CoreML fallback** (`u2netp` picks out one main object rather than instances, so the simulator is less precise than a device), provided the simulator has a signed-in account to download the model. This removes the need for a device build for M2, but an honest judgement of outline quality still needs an iPhone.

**Checked in the iPhone 17 Pro simulator, iOS 26.5** (the probe is a command-line Vision program run inside the simulator with `xcrun simctl spawn`, on the stock photos from the simulator's photo library):

| Request | Result in the simulator |
| --- | --- |
| `VNGenerateForegroundInstanceMaskRequest` (object cutout, iOS 17+) | **does not work**: `Could not create inference context`, also with `usesCPUOnly = true` |
| `VNGenerateObjectnessBasedSaliencyImageRequest` | fails by default (`Failed to create espresso context`); with `usesCPUOnly = true` it runs (~115 ms) but returned no objects on the test photos |
| `VNGenerateAttentionBasedSaliencyImageRequest` (`usesCPUOnly`) | works, ~220 ms |
| `VNDetectContoursRequest` | works, ~225 ms |
| `VNDetectRectanglesRequest`, `VNDetectHorizonRequest` | work |
| `VNRecognizeTextRequest(.fast)` | works, 100–220 ms |
| `VNDetectFaceRectanglesRequest`, `VNClassifyImageRequest`, feature print | do not work (no inference context) |

Conclusion on risk 2 of the brief: **the main effect (an object outline) is not available in the simulator**; Vision's neural-network requests need a device. In the simulator only the fallback path honestly works, a ring at the touch point, plus possible "geometric" hints (contours, rectangles, text in screenshots). A demo of the outline needs a run on an iPhone, signed with Nika's Apple ID. This changes the M2 plan and is discussed separately.

Probe source: `docs/visual-quote/tools/VisionProbe.swift` (to run: build with `xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator`, then `xcrun simctl spawn <udid> ./VisionProbe <image> 0.5 0.5`).

## 5. Carrying the coordinates without changing the schema

Facts to start from:
- `inputReplyToMessage` has no field for an image region, but it has two "inner subject" fields of a reply, `todo_item_id:int` and `poll_option:bytes` (`Api13.swift:352`), and they come back in `messageReplyHeader` (`Api18.swift:541`). The client fills them from `ReplyMessageAttribute.innerSubject` (`PendingMessageManager.swift:1240-1243`) and reads them back into `innerSubject`.
- A quote (`quote_text`) on a photo without a caption is impossible: the client creates a quote only for non-empty text (`ChatController.swift:4580-4589`), and on receipt builds it from `quoteText`/`replyMedia`.
- Outgoing attributes are filtered by an allowlist (`EnqueueMessage.swift:253-306`), and after the server confirms a message its attributes are replaced by the server's (`ApplyUpdateMessage.swift:258-263`): a local attribute will not reach the recipient and will not survive on the sender's side. The data has to travel in the message itself.
- Text entities: `textUrl` is coloured with the link colour without an underline (`StringWithAppliedEntities.swift:230-232, 292-304`); `customEmoji` with an unknown `document_id` is drawn as **empty space** the size of an emoji (`TextNodeWithEntities.swift:177-215`, `EmojiTextAttachmentView.swift:524`). Link previews are disabled with the `no_webpage` flag through `OutgoingContentInfoMessageAttribute([.disableLinkPreviews])` (`ChatControllerNode.swift:5296-5302`, `PendingMessageManager.swift:1795-1797`). Sending trims only spaces, tabs, line breaks and U+200C (`ChatTextInputAttributes.swift:1102, 1135`); U+200B stays.

In every option the data itself is the same: the kind (object/point), the touch point and the frame, normalized to 0…1 relative to the original, plus a format version. I suggest packing them into a short string/bytes with the magic prefix `VQ1`.

### Option A. The reply's `poll_option` field as a byte container
We put the encoded region into `innerSubject = .pollOption(bytes)`; existing code sends it in `poll_option`, the recipient gets it in `innerSubject`, and our UI recognizes the prefix.
- Pros: the data travels in the reply header itself, where it belongs; the message text stays clean; **not a single change to TelegramCore** (the existing path is used); in regular Telegram iOS the reply header of a photo without a poll does not find the option and shows an ordinary reply (`ChatMessageReplyInfoNode.swift:450` requires `TelegramMediaPoll`).
- Cons: the server may reject `poll_option` for a message without a poll; this is unknown and needs one test send at M3; other official clients (Android, Desktop) may behave differently on an unexpected `poll_option`, to be checked on Nika's phone; this abuses the field and is unacceptable in production.

### Option B. An invisible link in the text
A zero-width character (U+200B) with a `textUrl` entity is added to the reply text, and the URL carries the coordinates, for example `https://t.me/visual-quote#VQ1;o;0.512,0.377;0.41,0.30,0.22,0.19`; the link preview is disabled with `disableLinkPreviews`.
- Pros: the server will certainly accept it (ordinary entities); in regular Telegram the message looks like an ordinary reply: the zero-width character is invisible and there is no underline; also no changes to TelegramCore (the entities are assembled in the UI when sending and read in the UI when displaying).
- Cons: an invisible character appears in the text (it is copied along with the text); a long press exactly on the invisible character could in theory open the link; it needs non-empty reply text (in v0 there is always text; empty text cannot be substituted, since a space would be trimmed); a risk that some client shows an empty "tail" of the link.

### Option C. A custom emoji entity with the coordinates in `document_id`
A `messageEntityCustomEmoji` is attached to an emoji character (for example 📍), and the 64 bits of `document_id` encode x, y, w, h at 16 bits each.
- Pros: compact, no URL, the server will accept it.
- Cons: in regular Telegram there will be an **empty gap** in place of the emoji (the file does not resolve, the layer stays empty), which is exactly the "garbage" that requirement 2.10 does not allow; there is no room for the touch point and the kind; not recommended.

### What production would look like
A new case `EngineMessageReplyInnerSubject.imageRegion` and a field in `inputReplyToMessage`/`messageReplyHeader` next to `todo_item_id`/`poll_option`, for example `quote_region:flags.N?ImageRegion` (a type with four normalized coordinates and a point). The client side would then match the prototype one to one: only the encoding in `PendingMessageManager`/`StoreMessage_Telegram` changes. This has to be stated plainly in the README (section 2.11 of the brief).

The choice between A and B is Nika's after M1. My suggestion: implement the codec once, make the transport swappable, and at M3 try A first (one send will show whether the server accepts it), falling back to B if it does not.

## 6. Integration points and effort

Principle: new code goes into a new module, `submodules/TelegramUI/Components/VisualQuote` (the `VisualQuote` model, the transport codec, the highlight node, the fragment renderer), with thin entry points in existing files. TelegramCore is not touched: both workable transports do without it.

| # | What | Where to plug in | Effort |
| --- | --- | --- | --- |
| 1 | Model and codec | new module | ~1 day |
| 2 | Gallery gesture: long press on the photo | `ZoomableContentGalleryItemNode`: set `longTap` on the existing `TapLongTapOrDoubleTapGestureRecognizer` (`:46`) or handle `.longTap` in `contentTap` (`:104`); override in `ChatImageGalleryItemNode`; coordinate → normalized point through `scrollNode.view.convert` (`:88`) | 0.5 day |
| 3 | Selection: Vision | call `cutoutImage(from: imageNode.image, target: .point(p))` from `ImageObjectSeparation` (the module is already linked into TelegramUI); check `cutoutAvailability` (downloads the model in the simulator); fallback: a ring at the point | 1 day |
| 4 | Highlight | an overlay node over `imageNode` following `RecognizedContentContainer` (`ChatImageGalleryItem.swift:447`); the contour from the mask via `getPathFromMaskImage` from `StickerCutoutOutlineView` (moved into shared code without changing the original), a calm glow variant; haptics `HapticFeedback().impact(.light)`; **2 variants for Nika to choose from** | 1.5 days |
| 5 | "Reply" button | in the footer's glass group, `ChatItemGalleryFooterContentNode.updateLayout` (`:1334-1443`), or a separate button above the footer; the action is a copy of the "Reply" menu item (`ChatImageGalleryItem.swift:787-804`) that passes the region through `MessageHighlight.subject` / a new field; **variants for Nika to choose from** | 1 day |
| 6 | Composer: reply panel with the fragment | `ChatInterfaceState.ReplyMessageSubject` (add the region next to `innerSubject`, ChatInterfaceState module), `ChatInputMessageAccessoryPanel.Contents.Reply`: show the fragment (bring back the commented-out thumbnail `:489-510`, but cropped) | 1 day |
| 7 | Sending | `ChatControllerNode.sendCurrentMessage` (`:5024`): encode the region into the transport (A: `innerSubject = .pollOption(bytes)`; B: an entity + `disableLinkPreviews`) | 0.5 day |
| 8 | Recipient: header | `ChatMessageBubbleItemNode.swift:2149-2171, 3030-3046` → `ChatMessageReplyInfoNode`: decode the region from the message, draw an enlarged, highlighted fragment instead of the `imageSide` thumbnail; states "original not loaded" (thumbnail first) and "original deleted"; **2 size variants for Nika to choose from** | 2 days |
| 9 | Tap to navigate | `ChatMessageBubbleItemNode.swift:5990` → `navigateToMessage(... subject:)` → open the gallery on the message and zoom to the region: `scrollNode.view.zoom(to:)` after `activateAsInitial()` (`GalleryItemNode.swift:88`), taking into account the zoom reset in `resetScrollViewContents`; a short highlight | 1 day |
| 10 | Debug Settings flag, strings, VoiceOver | `ExperimentalUISettings` + `DebugController` (section 3); `en.lproj/Localizable.strings`; `accessibilityLabel` following `ReplyAccessoryPanelNode.swift:326-332` | 0.5 day |
| 11 | Theme checks, README, build from scratch | — | 1.5 days |

In total, roughly 11–12 working days of pure development, not counting approvals; every change is followed by a full build and a check in the simulator.

## 7. Open questions for Nika

1. Coordinate transport: A (`poll_option`) or B (invisible link). Suggestion: try A first at M3.
2. Vision in the simulator needs a signed-in account (the model is downloaded from a channel). Signing in to accounts remains a blocker for M2.
3. Where the "Reply" button lives: in the glass footer among the existing buttons, or as a separate button next to the selection. I will show both variants as screenshots at M2.
