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
        let markerLength = (marker as NSString).length
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
        let markerLength = (marker as NSString).length
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
