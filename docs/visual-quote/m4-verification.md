# M4 verification

Status as of 2026-10-13: the receiver path works end to end on one account across two simulators. The checks below are what has been exercised; everything else is still open.

## Automated

- Full `debug_sim_arm64` build (see D-002 in decisions.md).
- `python3 docs/visual-quote/tools/test-region-codec.py` compiles the region, codec and transport sources with stubs and runs 4081 checks: round trips, edge and corner regions, Float32 rounding at the image edge, malformed payloads, and the presentation filter for the transport entity.

## Verified in the simulator

- Opening a quote zooms to the region, centers it on screen and keeps the dim plus outline (variant B); the highlight follows pinch and double-tap zoom.
- A region touching the top-left corner and one touching the bottom edge are encoded, delivered to the second simulator and opened centered.
- A full-width strip of minimum height (44 pt) is delivered and opened correctly. Its square thumbnail is aspect-filled, so both ends are cut off in the reply header: open UX question.
- On a freshly signed-in device the header first shows a blurred crop from the thumbnail; after the app reconnected and the photo loaded, the crop became sharp.
- Deleting the original: the reply header disappears, exactly as for any reply to a deleted message in Telegram (D-022). No crash, no stale crop, no browser navigation.
- VoiceOver activation of a visual reply opens the gallery on the region instead of the hidden transport link in Safari.
- The transport entity no longer underlines the message text. Root cause (CoreText caret offset 0 for a trailing zero-width space) and the fix (marker first) are in D-023; verified in the dark theme with the presentation filter switched off, i.e. the way a stock client renders it (`screenshots/m4/16`).
- Editing a sent visual reply keeps the region. The composer extends the link onto the neighbouring word, so after an edit that word looks like a link (D-023).

## Still open

- Pinch and two-finger pan while the editable frame is active (D-021): built, not exercised by hand.
- A look at a new visual reply in stock Telegram on a phone, light and dark theme, to confirm the simulator result.
- A second account for a real incoming bubble (only one account is available).
- Narrow (minimum width) selections and the remaining two exact corners.
