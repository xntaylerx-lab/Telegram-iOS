#!/usr/bin/env python3
"""Run the production region/codec bodies on macOS without building Telegram.

UIKit imports are replaced by CoreGraphics for CGPoint/CGRect on macOS.
Telegram message/entity types are stubbed; no codec or transport logic is replaced.
The complete iOS build must still validate integration with the real modules.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]
source = root / 'submodules/TelegramUI/Components/VisualQuote/Sources'
parts = ['import Foundation\nimport CoreGraphics\npublic enum EngineMessageReplyInnerSubject { case pollOption(Data); case todoItem(Int32) }\n']
parts.append(r"""
public struct MessageTextEntity: Equatable {
    public enum Kind: Equatable { case TextUrl(url: String); case Bold; case Url }
    public let range: Range<Int>
    public let type: Kind
    public init(range: Range<Int>, type: Kind) { self.range = range; self.type = type }
}
public protocol MessageAttribute {}
public struct TextEntitiesMessageAttribute: MessageAttribute { public let entities: [MessageTextEntity] }
public struct RichTextMessageAttribute: MessageAttribute {}
public struct WebpagePreviewMessageAttribute: MessageAttribute {}
public struct OutgoingContentInfoFlags: OptionSet {
    public var rawValue: Int32
    public init() { self.rawValue = 0 }
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let disableLinkPreviews = OutgoingContentInfoFlags(rawValue: 1 << 0)
    public static let other = OutgoingContentInfoFlags(rawValue: 1 << 5)
}
public struct OutgoingContentInfoMessageAttribute: MessageAttribute {
    public let flags: OutgoingContentInfoFlags
    public init(flags: OutgoingContentInfoFlags) { self.flags = flags }
}
public struct Message { public let textEntitiesAttribute: TextEntitiesMessageAttribute? }
public struct MessageId: Equatable { public let id: Int32 }
public struct EngineMessageReplySubject: Equatable {
    public var messageId: MessageId
    public var quote: String?
    public var innerSubject: EngineMessageReplyInnerSubject?
    public init(messageId: MessageId, quote: String?, innerSubject: EngineMessageReplyInnerSubject?) {
        self.messageId = messageId; self.quote = quote; self.innerSubject = innerSubject
    }
}
extension EngineMessageReplyInnerSubject: Equatable {}
public struct MediaId: Hashable {}
public protocol Media {}
public struct AnyMediaReference {}
public struct StoryId {}
public struct ItemCollectionId {}
public enum EnqueueMessage {
    case message(text: String, attributes: [MessageAttribute], inlineStickers: [MediaId: Media], mediaReference: AnyMediaReference?, threadId: Int64?, replyToMessageId: EngineMessageReplySubject?, replyToStoryId: StoryId?, localGroupingKey: Int64?, correlationId: Int64?, bubbleUpEmojiOrStickersets: [ItemCollectionId])
    case forward(source: MessageId)
}
""")
for name in ['VisualQuoteRegion.swift', 'VisualQuoteCodec.swift', 'VisualQuoteTransport.swift']:
    parts.append('\n'.join(line for line in (source / name).read_text().splitlines()
                           if line not in ('import UIKit', 'import TelegramCore', 'import Postbox')))
parts.append(r'''
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    guard condition() else { fatalError("FAILED: \(label)") }
}
func payload(_ values: [Float32], kind: UInt8 = 0) -> Data {
    var result = Data([0x56, 0x51, 0x31, kind])
    for value in values {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
    }
    return result
}
func valid(_ values: [Float32], _ label: String, kind: UInt8 = 0) {
    let data = payload(values, kind: kind)
    guard let region = VisualQuoteRegion(encoded: data) else { fatalError("Rejected: \(label)") }
    check(region.rect.minX >= 0 && region.rect.minY >= 0 && region.rect.maxX <= 1 && region.rect.maxY <= 1, label)
    check(region.rect.width > 0 && region.rect.height > 0, label)
    check(VisualQuoteRegion(encoded: region.encoded()) != nil, "round trip \(label)")
    check(VisualQuoteRegion(innerSubject: region.innerSubject) != nil, "composer \(label)")
}
valid([0.5, 0.5, 0, 0, 1, 1], "full image")
valid([1, 1, 0.9, 0.9, 0.1, 0.1], "bottom/right float rounding", kind: 1)
valid([0, 0, 0, 0, 0.001, 0.001], "tiny top/left region")
valid([0.5, 0.5, 0.001, 0.001, 0.998, 0.998], "nearly full image")
valid([0.5, 0.5, 0.49, 0, 0.02, 1], "tall region")
valid([0.5, 0.5, 0, 0.49, 1, 0.02], "wide region")
for edge in 1...999 {
    let x = Float32(edge) / 1000
    valid([x, x, x, x, 1 - x, 1 - x], "edge \(edge)")
}

// Outgoing messages: the region leaves the reply subject and rides in the first text that has room.
let sampleRegion = VisualQuoteRegion(encoded: payload([0.5, 0.5, 0.25, 0.25, 0.5, 0.5], kind: 1))!
let subjectWithRegion = EngineMessageReplySubject(messageId: MessageId(id: 7), quote: nil, innerSubject: sampleRegion.innerSubject)
func outgoing(_ text: String, attributes: [MessageAttribute] = [], media: Bool = false, subject: EngineMessageReplySubject? = subjectWithRegion) -> EnqueueMessage {
    return .message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: media ? AnyMediaReference() : nil, threadId: nil, replyToMessageId: subject, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
}
func fields(_ message: EnqueueMessage) -> (text: String, attributes: [MessageAttribute], subject: EngineMessageReplySubject?) {
    guard case let .message(text, attributes, _, _, _, subject, _, _, _, _) = message else { fatalError("not a message") }
    return (text, attributes, subject)
}
func hasRegion(_ message: EnqueueMessage) -> Bool {
    let text = fields(message).text
    guard let attribute = fields(message).attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute else { return false }
    return text.hasPrefix(VisualQuoteTransport.marker) && attribute.entities.contains(where: { entity in
        if case let .TextUrl(url) = entity.type { return VisualQuoteTransport.region(fromUrl: url) == sampleRegion }
        return false
    })
}
func disablesPreviews(_ message: EnqueueMessage) -> Bool {
    return fields(message).attributes.contains(where: { ($0 as? OutgoingContentInfoMessageAttribute)?.flags.contains(.disableLinkPreviews) == true })
}
let limit = 4096
do {
    let result = VisualQuoteTransport.applyToOutgoing([outgoing("hello")], textLimit: limit, captionLimit: 1024)
    check(hasRegion(result[0]), "text message carries the region")
    check(fields(result[0]).subject?.innerSubject == nil, "text message reply subject is plain")
    check(fields(result[0]).subject?.messageId == MessageId(id: 7), "text message still replies to the photo")
    check(disablesPreviews(result[0]), "text message disables link previews")
}
do {
    let result = VisualQuoteTransport.applyToOutgoing([outgoing("", media: true)], textLimit: limit, captionLimit: 1024)
    check(!hasRegion(result[0]) && fields(result[0]).text == "", "media without a caption stays as it is")
    check(fields(result[0]).subject?.innerSubject == nil, "media without a caption replies plainly")
    check(!disablesPreviews(result[0]), "media without a caption gets no preview attribute")
}
do {
    let result = VisualQuoteTransport.applyToOutgoing([outgoing("caption", media: true)], textLimit: limit, captionLimit: 1024)
    check(hasRegion(result[0]), "media caption carries the region")
    let long = VisualQuoteTransport.applyToOutgoing([outgoing(String(repeating: "c", count: 1024), media: true)], textLimit: limit, captionLimit: 1024)
    check(!hasRegion(long[0]) && fields(long[0]).subject?.innerSubject == nil, "caption at its limit has no room")
}
do {
    let result = VisualQuoteTransport.applyToOutgoing([outgoing("first"), outgoing("second")], textLimit: limit, captionLimit: 1024)
    check(hasRegion(result[0]) && !hasRegion(result[1]), "only the first chunk carries the region")
    check(fields(result[1]).subject?.innerSubject == nil, "later chunks reply plainly")
    let full = VisualQuoteTransport.applyToOutgoing([outgoing(String(repeating: "x", count: limit)), outgoing("second")], textLimit: limit, captionLimit: 1024)
    check(!hasRegion(full[0]) && hasRegion(full[1]), "a full first chunk passes the region on")
}
do {
    let rich = VisualQuoteTransport.applyToOutgoing([outgoing("", attributes: [RichTextMessageAttribute()])], textLimit: limit, captionLimit: 1024)
    check(!hasRegion(rich[0]) && fields(rich[0]).subject?.innerSubject == nil, "rich message replies plainly")
    let kept = VisualQuoteTransport.applyToOutgoing([outgoing("link", attributes: [WebpagePreviewMessageAttribute()])], textLimit: limit, captionLimit: 1024)
    check(hasRegion(kept[0]) && !disablesPreviews(kept[0]), "an explicit preview is kept")
    let merged = VisualQuoteTransport.applyToOutgoing([outgoing("t", attributes: [OutgoingContentInfoMessageAttribute(flags: [.other])])], textLimit: limit, captionLimit: 1024)
    let infos = fields(merged[0]).attributes.compactMap { $0 as? OutgoingContentInfoMessageAttribute }
    check(infos.count == 1 && infos[0].flags.contains(.other) && infos[0].flags.contains(.disableLinkPreviews), "existing content flags are merged")
    let plain = VisualQuoteTransport.applyToOutgoing([outgoing("t", subject: EngineMessageReplySubject(messageId: MessageId(id: 7), quote: nil, innerSubject: nil)), .forward(source: MessageId(id: 1))], textLimit: limit, captionLimit: 1024)
    check(!hasRegion(plain[0]) && fields(plain[0]).subject?.messageId == MessageId(id: 7), "a plain reply is untouched")
    if case .forward = plain[1] {} else { fatalError("FAILED: forwards are untouched") }
    check(VisualQuoteTransport.withoutRegion(subjectWithRegion)?.innerSubject == nil, "withoutRegion strips the region")
    check(VisualQuoteTransport.withoutRegion(nil) == nil, "withoutRegion keeps nil")
}
// Chunks leave room for the marker in the first message.
func split(_ text: NSAttributedString) -> [NSAttributedString] {
    var result: [NSAttributedString] = []
    var offset = 0
    while offset < text.length {
        let length = min(limit, text.length - offset)
        result.append(text.attributedSubstring(from: NSRange(location: offset, length: length)))
        offset += length
    }
    return result
}
do {
    let short = VisualQuoteTransport.chunks(of: NSAttributedString(string: String(repeating: "a", count: 4000)), limit: limit, split: split)
    check(short.count == 1 && short[0].length == 4000, "short text is not re-split")
    let exact = VisualQuoteTransport.chunks(of: NSAttributedString(string: String(repeating: "a", count: limit)), limit: limit, split: split)
    check(exact.count == 2 && exact[0].length == limit - 1 && exact[1].length == 1, "text at the limit leaves one unit of room")
    let long = VisualQuoteTransport.chunks(of: NSAttributedString(string: String(repeating: "a", count: 9000)), limit: limit, split: split)
    check(long.map { $0.length } == [limit - 1, limit, 9000 - (limit - 1) - limit], "long text: first chunk short, the rest as usual")
    let emoji = NSAttributedString(string: String(repeating: "a", count: limit - 2) + "\u{1F600}" + "b")
    let kept = VisualQuoteTransport.chunks(of: emoji, limit: limit, split: split)
    check(kept[0].length == limit - 2 && (kept[0].string as NSString).length == limit - 2, "a surrogate pair is not cut in half")
    check(kept.map { $0.length }.reduce(0, +) == emoji.length, "nothing is lost when re-splitting")
}
let base: [Float32] = [0.5, 0.5, 0.2, 0.2, 0.3, 0.3]
for index in 0..<6 {
    for bad: Float32 in [.nan, .infinity, -.infinity, -.greatestFiniteMagnitude, .greatestFiniteMagnitude, -0.1, 1.1] {
        var values = base
        values[index] = bad
        check(VisualQuoteRegion(encoded: payload(values)) == nil, "invalid coordinate \(index): \(bad)")
    }
}
for values: [Float32] in [
    [0.5, 0.5, 0.9, 0.2, 0.2, 0.3],
    [0.5, 0.5, 0.2, 0.9, 0.3, 0.2],
    [0.5, 0.5, 0.2, 0.2, 0, 0.3],
    [0.5, 0.5, 0.2, 0.2, 0.3, 0],
    [0.5, 0.5, 1, 1, 0.0000001, 0.0000001]
] {
    check(VisualQuoteRegion(encoded: payload(values)) == nil, "invalid bounds")
}
check(VisualQuoteRegion(encoded: payload(base, kind: 2)) == nil, "unknown kind")
check(VisualQuoteRegion(encoded: Data()) == nil, "empty payload")
check(VisualQuoteRegion(encoded: payload(base).dropLast()) == nil, "truncated payload")
check(VisualQuoteRegion(encoded: payload(base) + Data([0])) == nil, "trailing bytes")
var wrongMagic = payload(base)
wrongMagic[0] = 0
check(VisualQuoteRegion(encoded: wrongMagic) == nil, "wrong magic")
check(VisualQuoteRegion(innerSubject: .todoItem(1)) == nil, "ordinary inner subject")
let transportRegion = VisualQuoteRegion(encoded: payload(base))!
let originalText = "👩🏽‍💻 Test"
let userLink = MessageTextEntity(range: 0..<2, type: .TextUrl(url: "https://telegram.org"))
let bold = MessageTextEntity(range: 2..<4, type: .Bold)
let originalEntities = [userLink, bold]
let attached = VisualQuoteTransport.attach(transportRegion, toText: originalText, entities: originalEntities)
check(attached.text == VisualQuoteTransport.marker + originalText, "marker prepended")
check(attached.entities.first!.range == 0..<1, "marker entity covers the first UTF-16 unit")
let shiftedEntities = originalEntities.map { MessageTextEntity(range: ($0.range.lowerBound + 1)..<($0.range.upperBound + 1), type: $0.type) }
check(VisualQuoteTransport.visibleEntities(attached.entities) == shiftedEntities, "preserve user links and formatting, shifted past the marker")
let expandedMetadata = MessageTextEntity(range: 0..<attached.text.utf16.count, type: .TextUrl(url: VisualQuoteTransport.url(for: transportRegion)))
check(VisualQuoteTransport.visibleEntities([expandedMetadata] + originalEntities) == originalEntities, "received full-text metadata never styles text")
let malformed = MessageTextEntity(range: 0..<2, type: .TextUrl(url: "https://example.com/visual-quote#invalid"))
check(VisualQuoteTransport.visibleEntities([malformed]) == [malformed], "do not swallow undecodable user URL")
check(VisualQuoteTransport.visibleEntities([]).isEmpty, "empty entities")
check(VisualQuoteTransport.region(in: Message(textEntitiesAttribute: TextEntitiesMessageAttribute(entities: attached.entities))) != nil, "stored metadata still decodes after filtering")
check(attached.entities.count == 3, "presentation filtering does not mutate storage")
let detached = VisualQuoteTransport.detach(text: attached.text, entities: attached.entities)
check(detached.text == originalText && detached.entities == originalEntities, "detach restores the editable text and entities")
let legacyText = originalText + VisualQuoteTransport.marker
let legacyEntities = originalEntities + [MessageTextEntity(range: originalText.utf16.count..<(originalText.utf16.count + 1), type: .TextUrl(url: VisualQuoteTransport.url(for: transportRegion)))]
let legacyDetached = VisualQuoteTransport.detach(text: legacyText, entities: legacyEntities)
check(legacyDetached.text == originalText && legacyDetached.entities == originalEntities, "detach handles the trailing marker of older messages")
let plain = VisualQuoteTransport.detach(text: originalText, entities: originalEntities)
check(plain.text == originalText && plain.entities == originalEntities, "detach leaves ordinary messages alone")
let movedEntities = originalEntities + [MessageTextEntity(range: 2..<4, type: .TextUrl(url: VisualQuoteTransport.url(for: transportRegion)))]
let moved = VisualQuoteTransport.detach(text: originalText, entities: movedEntities)
check(moved.text == originalText && moved.entities == originalEntities, "detach drops a displaced transport entity without touching the text")
print("PASS: \(checks) region codec and transport checks")
''')
with tempfile.TemporaryDirectory(prefix='visual-quote-codec-') as temp:
    temp = Path(temp)
    swift = temp / 'main.swift'
    swift.write_text('\n'.join(parts))
    binary = temp / 'codec-tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(temp / 'cache'), str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
