# Visual Quote for Telegram iOS

Reply to a detail of a photo the way you reply to a fragment of text.

This repository is a copy of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with a working prototype on the `visual-quote` branch. Telegram's original README with the compilation guide is [README.md](https://github.com/xntaylerx-lab/Telegram-iOS/blob/visual-quote/README.md) in the repository root.

## What it does

1. Hold a finger on a detail in the photo viewer. A frame snaps around the object under the finger. The frame is only a suggestion: drag its corners to resize it or drag inside to move it.
2. Tap **Reply** and type or dictate the answer.
3. The recipient sees the fragment in the reply header, styled like a text quote: the sender's name, the quote icon, and the fragment where the quoted text would be.
4. One tap on the header opens the original photo zoomed to that area, with everything around it dimmed.

Only a rectangle is sent. The recipient's client cuts the fragment out of the photo that is already in the chat, the same way a text quote points into the original message.

## Links

- [The prototype's changes only](https://github.com/xntaylerx-lab/Telegram-iOS/compare/master...visual-quote), without Telegram's own history.
- [Full write-up](https://github.com/xntaylerx-lab/Telegram-iOS/blob/visual-quote/docs/visual-quote/README.md): how to build it from scratch, what is real and what is temporary, how the region travels, where the code is.
- [Decision log](https://github.com/xntaylerx-lab/Telegram-iOS/blob/visual-quote/docs/visual-quote/decisions.md), in Russian.

## Status

A prototype, tested in the iOS 26 simulator on real accounts. It never ran on a physical iPhone. The Telegram API has no reply field for an image region, so the prototype carries the region as an invisible link in the reply text; production would need one new field in `inputReplyToMessage` and `messageReplyHeader`. All limits are listed in the write-up.
