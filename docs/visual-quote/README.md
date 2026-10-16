# Visual Quote prototype

Prototype of "Visual Quote" inside the official Telegram-iOS client: replying to a specific detail of a received photo the same way a text quote replies to a fragment of text. The recipient sees that detail in the reply header and one tap takes them to it in the original photo.

This is a prototype on the `visual-quote` branch. Everything below says plainly which parts work for real and which are temporary.

## The flow

1. Open a photo in the full-screen gallery and hold a finger on a detail.
2. A frame appears around it. Object separation suggests the frame around the object under the finger; when there is no confident object, the frame goes around the touch point. The rest of the photo is dimmed.
3. Adjust the frame: drag a corner to resize it, drag inside it to move it. Two fingers still zoom and pan the photo while the frame stays on the same part of it. Holding a finger elsewhere selects another detail; tapping outside clears the selection.
4. Tap **Reply**. The gallery closes, the chat's reply panel shows the selected fragment and the title "Reply to Quote from <name>", and the keyboard opens. Type the comment, or dictate it with the keyboard's dictation button.
5. The message is sent as an ordinary reply to the photo, with the region attached (see "How the region travels").
6. Both sides see the fragment in the reply header, styled like a text quote: sender colour, bar, name, quote icon, then the fragment instead of the quoted text.
7. Tapping the header opens the original photo zoomed to the region. Everything around the region is dimmed, the region has a thin outline, and the highlight follows zooming and scrolling until the gallery closes.

The feature sits behind a Debug Settings switch, "Visual Quote" (`ExperimentalUISettings.visualQuote`), which is on by default in this build. To open Debug Settings in a signed-in app, tap the Settings tab icon ten times quickly.

## Requirements (verified 2026-10-12)

- macOS 26, Xcode 26.6 (the version pinned in `versions.json`), iOS 26.5 simulator runtime.
- Xcode's **Metal Toolchain** component. Xcode 26 does not install it by default, and without it the build fails in `MetalCompile`. Installing it is a 688 MB download:
  ```sh
  xcodebuild -downloadComponent MetalToolchain
  ```
- Python 3 and about 20 GB of free disk space for the clone, the Bazel cache and the build outputs.
- Your own `api_id` / `api_hash` from https://my.telegram.org/apps.

## Build from scratch

### 1. Clone

Clone into a path without spaces. Bazel and the build scripts break on spaces, so `~/Developer` works but `~/Documents/Telegram contest` does not.

Clone Telegram's own repository, then fetch the prototype branch `visual-quote` from https://github.com/xntaylerx-lab/Telegram-iOS on top of it. Cloning that repository directly with `--recursive` fails: two submodules (`rlottie`, `tgcalls`) have relative URLs in `.gitmodules`, which resolve only under `github.com/TelegramMessenger`.

```sh
mkdir -p ~/Developer && cd ~/Developer
git clone --recursive https://github.com/TelegramMessenger/Telegram-iOS.git
cd Telegram-iOS
git fetch https://github.com/xntaylerx-lab/Telegram-iOS.git visual-quote:visual-quote
git checkout visual-quote
git submodule update --init --recursive
```

### 2. Build configuration

Copy `build-system/template_minimal_development_configuration.json` to a file **outside the repository**, for example `~/Developer/telegram-config/build-config.json`, and fill in `api_id` and `api_hash`. Never commit this file or print its keys.

The simulator build needs no developer account. It signs with the fake profiles shipped in `build-system/fake-codesigning`. Those profiles are issued for `team_id = C67CF9S4VU` and `bundle_id = ph.telegra.Telegraph`, and `Make.py` only picks profiles whose `application-identifier` equals `<team_id>.<bundle_id>`. So the configuration must use exactly these two values.

### 3. Build

From the repository root:

```sh
python3 build-system/Make/Make.py --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath="$HOME/Developer/telegram-config/build-config.json" \
  --codesigningInformationPath=build-system/fake-codesigning \
  --buildNumber=1 --configuration=debug_sim_arm64
```

A clean build takes about 10 minutes on an M1 Pro, an incremental one a few minutes. The result is `bazel-bin/Telegram/Telegram.ipa`. There is no partial build of single modules: every change is checked with a full build.

### 4. Install and run in the simulator

First install:

```sh
STAGE=$(mktemp -d)
unzip -q -o bazel-bin/Telegram/Telegram.ipa -d "$STAGE"
xcrun simctl install booted "$STAGE/Payload/Telegram.app"
xcrun simctl launch booted ph.telegra.Telegraph
```

After a rebuild with the same build number, `simctl install` silently keeps the old binary. Instead, copy the whole fresh `.app` over the installed bundle; the login survives because the data container is separate. The recipe is in the repository `CLAUDE.md`, under "Updating the running simulator after a rebuild".

Sign in with a real account. Telegram's test servers (`--ui-test`) reject the fixed login code for our `api_id` (decisions D-006, D-007), so the prototype was developed on real accounts.

### 5. Regression checks

```sh
python3 docs/visual-quote/tools/test-region-codec.py
```

This compiles the region, codec and transport sources with stubs and runs about 4,000 checks: round trips, edge and corner regions, Float32 rounding at the image edge, malformed payloads, and the presentation filter for the transport entity.

## What is real and what is temporary

**Works for real, in the real client:**
- Selection in the gallery: long press, an editable frame styled after Telegram's photo crop, a Reply button built from the gallery's own glass controls, light haptics (the same impact the context menu uses), and zooming the photo while the frame is active.
- Object suggestion uses the client's own object separation (`ImageObjectSeparation`, the one the sticker editor uses). On a device that is Vision subject lifting. In the simulator it is a CoreML fallback model (`u2netp`) that the client downloads on first use; it finds one salient object per photo, and a touch outside it gives a frame around the point. **Per-object suggestions on a device were not tested: the prototype never ran on an iPhone.** The frame can always be adjusted by hand, and only the rectangle is sent, so sender and recipient see exactly the same area either way.
- The message is a normal reply to the photo. The image is never sent again: the recipient's client cuts the fragment out of the original that is already in the chat, the same way a text quote refers to the text of the original message. Until the full photo is downloaded the fragment comes from the thumbnail (blurred), and it turns sharp once the photo loads.
- The bubble header, the reply panel over the composer, tap-to-open with zoom, VoiceOver labels, light and dark themes, other chat themes, and incoming and outgoing bubbles.
- Edge cases: regions at any edge or corner of the photo, strips of minimum width, an original far outside the loaded chat history, an original that was deleted (the header disappears like any reply to a deleted message), and editing a sent visual reply (the region is kept).
- Stock Telegram shows the message as an ordinary reply to the photo. This was checked on a phone in the dark theme.

**Temporary (prototype only):**
- **The transport of the region.** See the next section. This is the one thing that cannot ship as it is.
- The "Visual Quote" Debug Settings switch is on by default.
- One new string, `VisualQuote.VoiceOver.SelectedArea`, exists only in English. Other languages fall back to English. Everything else reuses existing localized strings.

**Not verified:**
- A visual reply as an **incoming** bubble in a private or group chat. Only one account was available. Incoming rendering was checked in a broadcast channel, where Telegram shows the owner's own posts as incoming.
- Running on a physical iPhone, which needs signing with an Apple ID.

## How the region travels (prototype vs. production)

A visual quote is a normal reply to the photo message plus the selected region: the touch point and a rectangle, both normalized to `0...1` relative to the original image, so they do not depend on the preview or original resolution.

The Telegram API has no field for an image region in `inputReplyToMessage` / `messageReplyHeader`, and the server drops reply fields it does not expect. We tried `poll_option`: the message was accepted, but the field came back empty.

**The prototype therefore carries the region inside the message itself.**
- **The marker.** A zero-width space is prepended to the reply text and tagged with a `textUrl` entity. Its URL is `https://example.com/visual-quote#<base64url payload>`, and link previews are disabled for the message. `example.com` is reserved for documentation and leads nowhere.
- **What stock clients see.** An ordinary reply to the photo: the zero-width glyph has no visible link styling.
- **Why the marker is first.** CoreText drops a trailing zero-width space from the glyph run. In themes where link colour equals text colour (e.g. the default dark theme), a trailing marker underlined the whole line.
- **What our client does.** It leaves the entity out of text rendering and VoiceOver, and opens the gallery instead of the URL. While a visual reply is being edited, it strips the marker and re-attaches the region on save.

**Known limits of this transport:**
- The region needs text to ride on. A text message or a media caption carries it; a sticker, a photo without a caption, a voice note, a dice, an inline bot result or a rich (markdown) message sent as a visual reply goes out as an ordinary reply to the photo, and so does an edit that turns a visual reply into rich content.
- A text or caption at its maximum length has no room for the marker; the composer leaves one character of room when it splits text into messages, and the editor's length limit is reduced by one.
- A cloud draft of a visual reply may lose the region: the composer keeps it in the reply subject's `poll_option`, which the server is known to drop on photo replies. Not verified (Saved Messages, the only chat available on both test devices, does not sync drafts at all).
- Editing the message in a stock client lets its composer extend the link onto the neighbouring word, or drop the link together with the region.
- In a stock client, a tap exactly on the zero-width marker opens the placeholder URL.

**In production** this would be a dedicated reply field next to `todo_item_id` / `poll_option` in `inputReplyToMessage` and `messageReplyHeader`, for example `quote_region`, serialized by TelegramCore like the other inner-subject fields. The client-side code (gallery selection, composer, bubble header, navigation) would not change: it already models the region as a reply inner subject (`EngineMessageReplyInnerSubject`). Locally the region rides in `.pollOption(bytes)` from the gallery to the composer, and only at send time is it moved into the text marker.

Payload format (`VisualQuoteRegion.encoded()`): ASCII `VQ1`, one byte for the kind (`1` object, `0` point), then six little-endian Float32: point x, y, then rect x, y, width, height.

## Where the code is

New code lives in its own module, `submodules/TelegramUI/Components/VisualQuote`:

| File | Role |
| --- | --- |
| `VisualQuoteRegion.swift`, `VisualQuoteCodec.swift` | the region model and its `VQ1` encoding |
| `VisualQuoteTransport.swift` | the temporary text-marker transport: attach, detach, read, presentation filter, and the outgoing-message transform |
| `VisualQuoteDetector.swift` | object suggestion via `ImageObjectSeparation` |
| `VisualQuoteFrameNode.swift`, `VisualQuoteShapes.swift` | the editable frame and the passive highlight |
| `VisualQuoteReplyButtonNode.swift` | the gallery Reply button |
| `VisualQuoteCropImage.swift` | the fragment in the bubble header and in the reply panel |

Existing files only get thin integration points:
- the gallery: `ChatImageGalleryItem.swift`, plus a long-press hook in `ZoomableContentGalleryItemNode.swift`;
- the reply panel: `ChatInputMessageAccessoryPanel.swift`;
- the bubble header: `ChatMessageReplyInfoNode.swift`;
- opening a quote and VoiceOver: `ChatMessageBubbleItemNode.swift`;
- keeping the marker out of the visible text: `ChatMessageTextBubbleContentNode.swift`;
- send and edit: `ChatController.swift` (`transformEnqueueMessages`, where the region leaves the reply subject for every send path), `ChatControllerNode.swift`, `ChatControllerLoadDisplayNode.swift` and `ChatControllerNavigateToMessage.swift`;
- the gallery subject: `GalleryController.swift` in AccountContext and `GalleryData.swift`;
- the flag: `ExperimentalUISettings.swift` and `DebugController.swift`.

TelegramCore is untouched.

## Further reading

- [decisions.md](decisions.md): every decision with its reason, D-001 to D-034.
- [code-map.md](code-map.md): how the relevant parts of Telegram-iOS work (M1).
- [m4-verification.md](m4-verification.md): what was checked on the recipient's side, with screenshot references.
- [m5-verification.md](m5-verification.md): the regression check of plain replies and text quotes, VoiceOver, and the clean build.
