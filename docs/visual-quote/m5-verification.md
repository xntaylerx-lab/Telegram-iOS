# M5 verification

Status as of 2026-10-13.

## Regression: plain replies and text quotes

Checked by hand in Nika's test channel with the prototype build (`screenshots/m5/01`-`04`):

- Swipe-to-reply on a message opens the stock panel "Reply to Test" with the message text and no fragment. The sent reply shows the stock header. Tapping the header scrolls to the original and flashes its bubble.
- Selecting a word in the message menu and choosing **Quote** opens the stock panel "Reply to Quote from Test". The sent reply shows the stock quote header with the quote icon. Tapping it scrolls to the original, flashes the bubble, then highlights the quoted word.

## VoiceOver

- The gallery Reply button appears in the runtime accessibility snapshot as `button "Reply"` (before D-032 it was an unnamed button). Its activation calls the same action as a tap; that was checked in code, not with VoiceOver turned on.
- The editable frame is labelled "Selected area" in code; the snapshot lists only tappable targets, so the label was not seen at runtime.
- A visual reply in the chat reads as a reply, without the transport URL, and activation opens the gallery on the region (checked in M4).

## Build from scratch (2026-10-13)

The commands from the README were run on the existing clone:
- `python3 build-system/Make/Make.py clean` (`bazel clean --expunge`, which removes all build outputs);
- then the README build command, with a new, empty `--cacheDir` (`~/telegram-bazel-cache-fresh`).

Result: `Build completed successfully, 7737 total actions` in 8 min 42 s on the M1 Pro. The `.ipa` from this build was installed by copying the whole `.app` and launched in both simulators, and the existing login survived.

Not covered: a fresh `git clone --recursive` and a machine without Xcode, the Metal Toolchain or Bazel's repository download cache. Those steps were done once at M0 (decisions D-001 to D-004).
