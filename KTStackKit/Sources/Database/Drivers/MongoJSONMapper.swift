import Foundation
import MongoKitten

enum MongoJSONMapper {
    enum Hint {
        static let objectId = "$oid"
        static let date = "$date"
        static let decimal = "$numberDecimal"
        static let binary = "$binary"
        static let timestamp = "$timestamp"
    }

    static func encodedJSON(from document: Document, pretty: Bool) throws -> String {
        let object = jsonObject(from: document)
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed]
        if pretty { options.insert(.prettyPrinted); options.insert(.sortedKeys) }
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        return String(decoding: data, as: UTF8.self)
    }

    static func identifierJSON(for primitive: Primitive?) -> String? {
        guard let primitive else { return nil }
        let object = jsonValue(from: primitive)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func displayString(for primitive: Primitive?) -> String {
        switch primitive {
        case let id as ObjectId: id.hexString
        case let s as String: s
        case let value?: String(describing: value)
        case nil: "—"
        }
    }

    static func document(fromJSON json: String) throws -> Document {
        let data = Data(json.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let dictionary = parsed as? [String: Any] else {
            throw DatabaseError.syntax("A document must be a JSON object.")
        }
        return buildDocument(from: dictionary)
    }

    static func value(fromJSON json: String) throws -> Primitive {
        let data = Data(json.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return primitive(from: parsed)
    }

    private static func jsonObject(from document: Document) -> Any {
        if document.isArray {
            return document.values.map(jsonValue(from:))
        }
        var result: [String: Any] = [:]
        for (key, value) in document {
            result[key] = jsonValue(from: value)
        }
        return result
    }

    private static func jsonValue(from primitive: Primitive) -> Any {
        switch primitive {
        case let nested as Document: jsonObject(from: nested)
        case let id as ObjectId: [Hint.objectId: id.hexString]
        case let date as Date: [Hint.date: ISO8601DateFormatter.mongo.string(from: date)]
        case let decimal as Decimal128: [Hint.decimal: String(describing: decimal)]
        case let binary as Binary: [Hint.binary: binary.data.base64EncodedString()]
        case let stamp as Timestamp: [Hint.timestamp: ["t": Int(stamp.timestamp), "i": Int(stamp.increment)]]
        case is Null: NSNull()
        case let bool as Bool: bool
        case let int as Int: int
        case let int as Int32: Int(int)
        case let int as Int64: Int(int)
        case let double as Double: double
        case let string as String: string
        default: String(describing: primitive)
        }
    }

    private static func buildDocument(from dictionary: [String: Any]) -> Document {
        var document = Document()
        for (key, value) in dictionary {
            document[key] = primitive(from: value)
        }
        return document
    }

    private static func primitive(from any: Any) -> Primitive {
        switch any {
        case let dictionary as [String: Any]:
            if let hinted = hintedPrimitive(dictionary) { return hinted }
            return buildDocument(from: dictionary)
        case let array as [Any]:
            var document = Document(isArray: true)
            for element in array {
                document.append(primitive(from: element))
            }
            return document
        case let string as String:
            return string
        case is NSNull:
            return Null()
        case let number as NSNumber:
            return numberPrimitive(number)
        default:
            return String(describing: any)
        }
    }

    private static func hintedPrimitive(_ dictionary: [String: Any]) -> Primitive? {
        guard dictionary.count == 1 else { return nil }
        if let hex = dictionary[Hint.objectId] as? String, let id = ObjectId(hex) {
            return id
        }
        if let iso = dictionary[Hint.date] as? String,
           let date = ISO8601DateFormatter.mongo.date(from: iso)
        {
            return date
        }
        if let base64 = dictionary[Hint.binary] as? String, let data = Data(base64Encoded: base64) {
            return data
        }
        if let stamp = dictionary[Hint.timestamp] as? [String: Any],
           let timestamp = (stamp["t"] as? NSNumber)?.int32Value,
           let increment = (stamp["i"] as? NSNumber)?.int32Value
        {
            return Timestamp(increment: increment, timestamp: timestamp)
        }
        // BSON 8.x exposes no public Decimal128 string initializer, so a $numberDecimal hint cannot be
        // reconstructed; editing a document that contains one re-stores that field as a sub-document.
        return nil
    }

    private static func numberPrimitive(_ number: NSNumber) -> Primitive {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        if CFNumberIsFloatType(number) { return number.doubleValue }
        return Int(number.int64Value)
    }
}

extension ISO8601DateFormatter {
    static let mongo: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
