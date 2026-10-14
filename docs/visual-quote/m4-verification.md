# M4 verification

Status as of 2026-10-13: the receiver path works end to end on one account across two simulators. The checks below are what has been exercised; everything else is still open.

## Automated

- Full `debug_sim_arm64` build (see D-002 in decisions.md).
- `python3 docs/visual-quote/tools/test-region-codec.py` compiles the region, codec and transport sources with stubs and runs 4081 checks: round trips, edge and corner regions, Float32 rounding at the image edge, malformed payloads, and the presentation filter for the transport entity.

## Verified in the simulator

- Opening a quote zooms to the region as close to the middle as the photo allows (no empty space beyond its edge, D-028) and keeps the dim plus outline (variant B); the highlight follows pinch and double-tap zoom.
- A region touching the top-left corner and one touching the bottom edge are encoded, delivered to the second simulator and opened centered.
- A full-width strip of minimum height (44 pt) is delivered and opened correctly. Since D-026 the header shows it whole (aspect-shaped thumbnail, short side at least a quarter, fitted when clamped).
- On a freshly signed-in device the header first shows a blurred crop from the thumbnail; after the app reconnected and the photo loaded, the crop became sharp.
- Deleting the original: the reply header disappears, exactly as for any reply to a deleted message in Telegram (D-022). No crash, no stale crop, no browser navigation.
- With the editable frame active: pinch out, pinch in and a two-finger pan all move the photo while the frame stays on the same part of it and the Reply button follows; one finger still moves the frame, and Reply produces the crop the frame showed (`screenshots/m4/20` video, `21`-`25`).
- Replying from a photo that is not in the loaded chat history (opened from the profile's Media tab, or an album photo far up the chat) keeps the region (D-025). Album photos opened from the chat itself: first and third photo of an album both deliver and open correctly.
- Opening a quote whose original is outside the loaded history (a photo from months ago) opens the standalone gallery zoomed to the region instead of scrolling the chat (D-027, `screenshots/m4/37`).
- VoiceOver activation of a visual reply opens the gallery on the region instead of the hidden transport link in Safari.
- Confirmed by Nika on her phone in stock Telegram, dark theme: a visual reply with the leading marker shows no underline and no link colour (2026-10-13).
- The transport entity no longer underlines the message text. Root cause (CoreText caret offset 0 for a trailing zero-width space) and the fix (marker first) are in D-023; verified in the dark theme with the presentation filter switched off, i.e. the way a stock client renders it (`screenshots/m4/16`).
- Editing a sent visual reply keeps the region: the marker is stripped in the editor and re-attached on save (D-024). Checked on a message with the leading marker and on an older one with the trailing marker.

## Still open

- A second account for a real incoming bubble (only one account is available).
- Narrow (minimum width) selections and the remaining two exact corners.
