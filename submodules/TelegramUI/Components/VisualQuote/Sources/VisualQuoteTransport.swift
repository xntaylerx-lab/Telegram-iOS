import Foundation
import UIKit
import TelegramCore
import Postbox

/// Carries a region on a regular reply message without a schema change.
///
/// The reply header has no field for an image region, and the server drops unknown reply data
/// (it silently discards `poll_option` on a reply to a photo). So the prototype prepends a
/// zero-width space to the message text and gives it a `TextUrl` entity whose URL holds the
/// encoded region; link previews are disabled for the message. Our own client additionally
/// leaves this entity out of text rendering (`visibleEntities`). In production this would be a
/// dedicated reply field next to `todo_item_id` / `poll_option`; see the README.
public enum VisualQuoteTransport {
    /// The invisible character the entity is attached to.
    public static let marker: String = "\u{200B}"
    /// The marker's length in UTF-16 units, the unit of entity ranges and message length limits.
    public static let markerLength: Int = (marker as NSString).length
    /// example.com is reserved for documentation, so the link never resolves to anything real.
    private static let urlPrefix: String = "https://example.com/visual-quote#"
    
    public static func url(for region: VisualQuoteRegion) -> String {
        let payload = region.encoded().base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return urlPrefix + payload
    }
    
    public static func region(fromUrl url: String) -> VisualQuoteRegion? {
        guard url.hasPrefix(urlPrefix) else {
            return nil
        }
        var payload = String(url.dropFirst(urlPrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload) else {
            return nil
        }
        return VisualQuoteRegion(encoded: data)
    }
    
    /// Prepends the marker and its entity to an outgoing text; the other entities shift right by
    /// the marker's length. Entity ranges are UTF-16 offsets.
    ///
    /// The marker is the first character on purpose. CoreText drops a trailing zero-width space
    /// from the glyph run and reports caret offset 0 for its index, so a link underline on a
    /// trailing marker stretches across the whole line (seen in stock Telegram in themes where
    /// links are underlined). For a leading marker both caret offsets are 0 and nothing is drawn.
    public static func attach(_ region: VisualQuoteRegion, toText text: String, entities: [MessageTextEntity]) -> (text: String, entities: [MessageTextEntity]) {
        let shifted = entities.map { entity in
            MessageTextEntity(range: (entity.range.lowerBound + markerLength) ..< (entity.range.upperBound + markerLength), type: entity.type)
        }
        return (marker + text, [MessageTextEntity(range: 0 ..< markerLength, type: .TextUrl(url: url(for: region)))] + shifted)
    }
    
    /// Removes the marker and its entity from a message's text for editing, shifting the other
    /// entities back. Works for the marker at either end (older messages carried it last). The
    /// region itself is read from the original message again and re-attached when the edit is saved.
    public static func detach(text: String, entities: [MessageTextEntity]) -> (text: String, entities: [MessageTextEntity]) {
        guard let index = entities.firstIndex(where: { entity in
            if case let .TextUrl(url) = entity.type, region(fromUrl: url) != nil {
                return true
            }
            return false
        }) else {
            return (text, entities)
        }
        let nsText = text as NSString
        var remaining = entities
        remaining.remove(at: index)
        let markerLocation = entities[index].range.lowerBound
        guard markerLocation >= 0, markerLocation + markerLength <= nsText.length, nsText.substring(with: NSRange(location: markerLocation, length: markerLength)) == marker else {
            return (text, remaining)
        }
        let strippedText = nsText.replacingCharacters(in: NSRange(location: markerLocation, length: markerLength), with: "")
        let shifted = remaining.map { entity -> MessageTextEntity in
            if entity.range.lowerBound >= markerLocation + markerLength {
                return MessageTextEntity(range: (entity.range.lowerBound - markerLength) ..< (entity.range.upperBound - markerLength), type: entity.type)
            }
            return entity
        }
        return (strippedText, shifted)
    }
    
    /// Excludes decoded metadata from text styling and link hit testing without changing
    /// the stored entities used to reconstruct the quote. Keep all UTF-16 offsets intact.
    public static func visibleEntities(_ entities: [MessageTextEntity]) -> [MessageTextEntity] {
        return entities.filter { entity in
            if case let .TextUrl(url) = entity.type, region(fromUrl: url) != nil {
                return false
            }
            return true
        }
    }

    /// The reply subject without the region: what every outgoing message carries once the region has
    /// moved into the text, and what a send that cannot carry text (an inline bot result) uses.
    public static func withoutRegion(_ subject: EngineMessageReplySubject?) -> EngineMessageReplySubject? {
        guard let subject, VisualQuoteRegion(innerSubject: subject.innerSubject) != nil else {
            return subject
        }
        return EngineMessageReplySubject(messageId: subject.messageId, quote: subject.quote, innerSubject: nil)
    }
    
    /// Moves the region from the composer's reply subject into the text of the first message that has
    /// room for it (a text message or a media caption); every message goes out with a plain reply.
    /// Sends that have no text to carry the marker (stickers, media without a caption, dice, rich
    /// messages) become ordinary replies to the photo.
    public static func applyToOutgoing(_ messages: [EnqueueMessage], textLimit: Int, captionLimit: Int) -> [EnqueueMessage] {
        var attached = false
        return messages.map { message in
            guard case let .message(originalText, originalAttributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, let subject = replyToMessageId, let region = VisualQuoteRegion(innerSubject: subject.innerSubject) else {
                return message
            }
            var text = originalText
            var attributes = originalAttributes
            let limit = mediaReference != nil ? captionLimit : textLimit
            let isRich = attributes.contains(where: { $0 is RichTextMessageAttribute })
            if !attached && !text.isEmpty && !isRich && (text as NSString).length + markerLength <= limit {
                var entities: [MessageTextEntity] = []
                for attribute in attributes {
                    if let attribute = attribute as? TextEntitiesMessageAttribute {
                        entities = attribute.entities
                        break
                    }
                }
                (text, entities) = attach(region, toText: text, entities: entities)
                attributes.removeAll(where: { $0 is TextEntitiesMessageAttribute })
                attributes.append(TextEntitiesMessageAttribute(entities: entities))
                // The marker's URL must not become a link preview; an explicit preview the user kept wins.
                if !attributes.contains(where: { $0 is WebpagePreviewMessageAttribute }) {
                    var flags = OutgoingContentInfoFlags()
                    if let index = attributes.firstIndex(where: { $0 is OutgoingContentInfoMessageAttribute }), let current = attributes[index] as? OutgoingContentInfoMessageAttribute {
                        flags = current.flags
                        attributes.remove(at: index)
                    }
                    flags.insert(.disableLinkPreviews)
                    attributes.append(OutgoingContentInfoMessageAttribute(flags: flags))
                }
                attached = true
            }
            return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: withoutRegion(subject), replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        }
    }
    
    /// Splits composer text into messages with `split`, making sure the first chunk leaves room for the
    /// marker under `limit`: `split` alone fills a chunk to the limit, and `applyToOutgoing` would then
    /// find no room. Only the first chunk is cut shorter; the rest is split as usual.
    public static func chunks(of text: NSAttributedString, limit: Int, split: (NSAttributedString) -> [NSAttributedString]) -> [NSAttributedString] {
        let chunks = split(text)
        let room = limit - markerLength
        guard let first = chunks.first, first.length > room, text.length > room, room > 0 else {
            return chunks
        }
        var headLength = room
        let composed = (text.string as NSString).rangeOfComposedCharacterSequence(at: room - 1)
        if composed.upperBound > room {
            headLength = composed.location
        }
        guard headLength > 0 else {
            return chunks
        }
        let head = text.attributedSubstring(from: NSRange(location: 0, length: headLength))
        let rest = text.attributedSubstring(from: NSRange(location: headLength, length: text.length - headLength))
        return [head] + split(rest)
    }
    
    /// The region carried by a message, if any.
    public static func region(in message: Message) -> VisualQuoteRegion? {
        guard let entities = message.textEntitiesAttribute?.entities else {
            return nil
        }
        for entity in entities {
            if case let .TextUrl(url) = entity.type, let region = region(fromUrl: url) {
                return region
            }
        }
        return nil
    }
}
