# Visual Quote prototype

Prototype of "Visual Quote": replying to a specific detail of a received photo inside the official Telegram-iOS client, the same way a text quote replies to a fragment of text.

Work in progress. This file will grow with each milestone; for now it records how to build and run the simulator build.

## Requirements (verified 2026-10-12)

- macOS 26, Xcode 26.6 (the version pinned in `versions.json`), iOS 26.5 simulator runtime.
- Xcode's **Metal Toolchain** component. It is not installed with Xcode 26 by default and the build fails in `MetalCompile` without it:
  ```sh
  xcodebuild -downloadComponent MetalToolchain
  ```
- Python 3, ~20 GB of free disk space (clone, Bazel cache and outputs).
- A build configuration JSON (see `build-system/template_minimal_development_configuration.json`) with your own `api_id` / `api_hash` from https://my.telegram.org/apps. Keep it outside the repository.

## Simulator build without a developer account

Code signing is not needed in the simulator. The build uses the fake profiles shipped in `build-system/fake-codesigning`. Those profiles are issued for `team_id = C67CF9S4VU` and `bundle_id = ph.telegra.Telegraph`, and `Make.py` only picks profiles whose `application-identifier` equals `<team_id>.<bundle_id>`, so the configuration JSON must use exactly these two values.

From the repository root:

```sh
python3 build-system/Make/Make.py --cacheDir="$HOME/telegram-bazel-cache" build \
  --configurationPath="$HOME/Developer/telegram-config/build-config.json" \
  --codesigningInformationPath=build-system/fake-codesigning \
  --buildNumber=1 --configuration=debug_sim_arm64
```

A clean build takes about 10 minutes on an M1 Pro. The result is `bazel-bin/Telegram/Telegram.ipa`.

## Install and run in the simulator

```sh
STAGE=$(mktemp -d)
unzip -q -o bazel-bin/Telegram/Telegram.ipa -d "$STAGE"
xcrun simctl install booted "$STAGE/Payload/Telegram.app"
xcrun simctl launch booted ph.telegra.Telegraph
```

When reinstalling a rebuilt app with the same build number, copy the whole `.app` over the installed bundle instead of `simctl install` (see the repository `CLAUDE.md`, "Updating the running simulator after a rebuild").

## Telegram test servers

Launching with the `--ui-test` argument makes the client use Telegram's test datacenters and an isolated data directory that is wiped on every launch. Test phone numbers are `+999 66X YYYY` and the login code is the DC digit `X` repeated five times (see `docs/ui-testing.md`).

## How the region travels (prototype vs. production)

A visual quote is a normal reply to the photo message plus the selected region: the touch point and a rectangle, both normalized to `0...1` relative to the original image.

The Telegram API has no field for an image region in `inputReplyToMessage` / `messageReplyHeader`, and the server drops reply fields it does not expect (we tried `poll_option`: the message is accepted, the field comes back empty). **The prototype therefore carries the region inside the message itself:** a zero-width space is prepended to the reply text and tagged with a `textUrl` entity whose URL is `https://example.com/visual-quote#<base64url payload>`; link previews are disabled for the message. Regular Telegram clients show the message as an ordinary reply to the photo: the zero-width glyph has no visible link styling. The marker must be the *first* character: CoreText drops a trailing zero-width space from the glyph run and reports caret offset 0 for its index, so in themes where links are underlined (link colour equals text colour, e.g. the default dark theme) a trailing marker produced an underline across the whole line. Our client also leaves the entity out of text rendering and VoiceOver, and opens the gallery instead of the URL. Our client also strips the marker while a visual reply is being edited and re-attaches the region on save, so edits keep the quote. Known limits: editing the message in a stock client lets its composer extend the link onto the neighbouring word or drop it together with the region, and a tap exactly on the marker in a stock client opens the placeholder URL. This is a temporary transport and is documented as such.

**In production** this would be a dedicated reply field next to `todo_item_id` / `poll_option` (for example `quote_region`), serialized by TelegramCore like the other inner-subject fields. The client-side code (gallery selection, composer, bubble header, navigation) would not change: it already models the region as a reply inner subject.

Payload format (`VisualQuoteRegion.encoded()`): ASCII `VQ1`, one byte kind (`1` object, `0` point), then six little-endian Float32: point x, y; rect x, y, width, height.

## Current verification status (2026-10-13)

M4 remains in progress. The current fragment size is 8 title-line heights, and opening a
quote centers the region with persistent dimming and a thin outline (variant B, approved by Nika on 2026-10-13). Development uses real accounts without `--ui-test`; test-DC
sign-in with our configuration failed, as recorded in decisions D-006/D-007.

Run the isolated region codec regression checks from the repository root:

```sh
python3 docs/visual-quote/tools/test-region-codec.py
```

See [M4 verification](m4-verification.md) for completed checks, test limitations, and the
interactive cases still needed before closing M4.
