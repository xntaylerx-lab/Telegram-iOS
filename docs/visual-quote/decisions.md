# Visual Quote — decision log

What was decided while building the prototype, and why. Each entry is one decision; replaced decisions stay in the list, marked, so the numbers other documents refer to stay valid. "Nika" marks the design calls made by the author.

## Environment (2026-10-12)

**D-001. The clone lives in `~/Developer/Telegram-iOS`.** The build breaks on paths with spaces, and Documents may sync with iCloud.

**D-002. The simulator build uses `Make.py build` with the repository's fake signing.** It produces a ready app without an Apple developer team. The command is in the README.

**D-003. The build configuration uses Telegram's own team and bundle ids.** The fake signing profiles match only that pair. This is fine for the simulator; a distributed build would need its own ids. The configuration with the API keys lives outside the repository.

**D-004. Xcode 26 needs the Metal Toolchain component**, a separate download. It is listed in the README requirements.

**D-005. Telegram's test servers are reachable only with the `--ui-test` launch argument**, which wipes the login on every launch.

**D-006. Develop on the test servers.** Replaced by D-007.

**D-007. Develop on real accounts.** The test servers rejected the fixed login code for our api_id, and nothing in the client could change that.

## Selection (2026-10-12 – 13)

**D-008. Object suggestion reuses Telegram's own object separation**, the one behind sticker cutouts. New code lives in its own `VisualQuote` module, and the feature sits behind a Debug Settings switch.

**D-009. Two simulator-only fixes in the detector**, so the simulator's fallback model returns a correct mask. That model finds one main object per photo; per-object suggestions need a device.

**D-010. Interactive checks run in the iOS simulator.** Screenshots of private chats stay out of reports.

**D-011. The selection is an editable frame, not an object outline (Nika).** It works like Telegram's photo crop: corners resize, dragging inside moves, the rest of the photo is dimmed. Object detection only suggests the starting frame. Why: it mirrors adjusting a text selection; only a rectangle is sent, so both sides see exactly the same area; and it works the same whatever the detection quality.

## Sending (2026-10-13)

**D-012. The region travels as an invisible link in the reply text.** The server silently drops the reply field we tried first (`poll_option`). So a zero-width character carries a link to `example.com/visual-quote#<region>`, a reserved domain that leads nowhere, with link previews off. Stock Telegram shows an ordinary reply to the photo. In production this would be one new reply field next to `poll_option`.

**D-013. The reply panel above the input field shows the selected fragment.**

## Recipient (2026-10-13)

**D-014. The reply header shows the fragment, cut from the original photo already in the chat**, larger than the usual reply thumbnail. Nika chose the largest of four sizes. If the original is unavailable, the reply looks like any other reply.

**D-015. Tapping the header opens the original photo zoomed to the region.** How the region is marked there was replaced by D-016.

**D-016. When a quote is opened, everything around the region is dimmed, and stays dimmed (Nika).** No frame or handles: a frame looks like an invitation to edit. The final look is D-019.

**D-017. Centre the region even if that shows empty space beyond the photo's edge (Nika).** Replaced by D-028.

**D-018. Malformed regions are rejected** when a message is read, and tiny rounding errors at the photo's edge are tolerated.

**D-019. The opened quote is marked by 45% dimming and a thin white outline (Nika)**, chosen over stronger dimming without an outline. The dimming matches Telegram's crop editor.

**D-020. Keep a placeholder when the original is deleted (Nika).** Replaced by D-022.

**D-021. The photo can be zoomed while a frame is active (Nika).** One finger edits the frame, two fingers zoom and pan the photo, and the frame stays on the same part of it.

**D-022. If the original is deleted, the header disappears, as for any reply to a deleted message (Nika).** Same logic as the rest of the app, and no flicker while history loads.

**D-023. The invisible marker goes first in the text, not last.** At the end it made the whole line look underlined in themes where links and text share a colour.

**D-024. Editing a visual reply keeps the region.** Our client takes the marker out of the editor and puts it back on save. In stock Telegram an edit can still move or drop it; this is listed in the README as a transport limit.

**D-025. Replying works for a photo opened outside the loaded chat history**, for example from the profile's media or from search. The region used to get lost there.

**D-026. The header is built like a text quote's (Nika):** the sender's name, the quote icon, and the fragment where the quoted text would be, with no "Photo" line. A narrow strip is shown whole, and a wide fragment takes the full width of the header, like a long text quote.

**D-027. Opening a quote works even when the original is far back in the chat history.**

**D-028. Zooming to the region stops at the photo's edge and shows no empty space (Nika).** Replaces D-017.

**D-029. A region at the photo's edge never hides under the gallery's controls (Nika).** The photo shifts just enough to show it between them, and the shift goes away as soon as the user moves the photo.

**D-030. The reply panel shows the whole fragment, not a square crop (Nika).** Very thin fragments get their own rounded corners.

**D-031. The reply panel says "Reply to Quote from <name>", as for a text quote (Nika).** No new strings were needed. The title gets truncated in the narrow panel; Nika kept it that way rather than shrink the fragment.

## Polish (2026-10-13)

**D-032. VoiceOver labels for the Reply button and the selection frame.** "Selected area" is the prototype's only new string; other languages fall back to English.

**D-033. The gallery frame uses fixed colours rather than theme colours (Nika).** The gallery is always dark, and Telegram's crop editor does the same.

## Review before publication (2026-10-13)

**D-034. Every way of sending a reply handles the region**, in one place that all sends pass through. A reply without text (a sticker, a voice message, a photo without a caption) goes out as an ordinary reply; this and the other transport limits are in the README. The same review fixed several smaller issues, such as hiding selection in chats that forbid copying.

**D-035. The code is published in Nika's own GitHub repository**, with Telegram's full history and `visual-quote` as the default branch, after a check for keys and personal data. Private at first, public since 2026-10-16.

## Demo video (2026-10-15 – 16)

**D-036. A debug touch indicator for recording the demo**, active only with the `--show-touches` launch argument. It is a recording tool, not part of the feature.

**D-037. A fast drag from a corner resizes the frame instead of moving it.** Found while recording: the gesture now picks a corner or a move by where the finger first touched.

## Publication (2026-10-16 – 17)

**D-038. The repository page opens on Visual Quote, not on Telegram's compilation guide (Nika).** GitHub shows `.github/README.md` first; Telegram's own README stays unchanged.

**D-039. The documentation is in English (Nika).** The log and the code map were translated from Russian.

**D-040. The prototype's commits carry no Claude co-author line (Nika).** The branch history was rewritten to remove it. Telegram's own history, which this repository carries, still has such commits.

**D-041. This log is kept short (Nika):** one decision per entry, what and why. The detailed working log, with checks and screenshot references, is in git history.
