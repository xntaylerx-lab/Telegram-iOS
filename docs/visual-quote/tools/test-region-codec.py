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
public struct TextEntitiesMessageAttribute { public let entities: [MessageTextEntity] }
public struct Message { public let textEntitiesAttribute: TextEntitiesMessageAttribute? }
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
