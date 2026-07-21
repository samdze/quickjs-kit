internal import Foundation

internal enum BindingTypeShape: Sendable, Hashable {
    case void
    case unknown
    case null
    case undefined
    case boolean
    case string
    case bigInt
    case floatingPoint(String)
    case integer(name: String, signed: Bool, bits: Int)
    indirect case optional(BindingTypeShape)
    indirect case array(BindingTypeShape)
    indirect case dictionary(BindingTypeShape)
    case data
    case date
    case url
    case codable(swiftName: String, schema: TypeScriptSchema?)
}

internal struct BindingParameterDescription: Sendable, Hashable {
    internal let name: String
    internal let type: BindingTypeShape
}

internal struct BindingDescription: Sendable, Hashable {
    internal enum Location: Sendable, Hashable {
        case global
        case objectExport(name: String)
        case module(specifier: String)
    }

    internal struct Effects: Sendable, Hashable {
        internal let isAsync: Bool
        internal let isThrowing: Bool
    }

    internal let location: Location
    internal let name: String
    internal let parameters: [BindingParameterDescription]
    internal let result: BindingTypeShape
    internal let effects: Effects
    internal let documentation: String?
    internal let order: UInt64
}

internal struct BindingDraft: Sendable {
    internal let name: String
    internal let parameters: [BindingParameterDescription]
    internal let result: BindingTypeShape
    internal let effects: BindingDescription.Effects
    internal let documentation: String?

    internal func finalize(
        location: BindingDescription.Location,
        order: UInt64
    ) -> BindingDescription {
        BindingDescription(
            location: location,
            name: name,
            parameters: parameters,
            result: result,
            effects: effects,
            documentation: documentation,
            order: order
        )
    }
}

internal protocol BindingTypeShapeProviding {
    static var bindingTypeShape: BindingTypeShape { get }
}

extension Bool: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .boolean
}

extension String: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .string
}

extension Float: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .floatingPoint("Float")
}

extension Double: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .floatingPoint("Double")
}

extension Int: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(
        name: "Int", signed: true, bits: Int.bitWidth
    )
}

extension Int8: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "Int8", signed: true, bits: 8)
}

extension Int16: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "Int16", signed: true, bits: 16)
}

extension Int32: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "Int32", signed: true, bits: 32)
}

extension Int64: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "Int64", signed: true, bits: 64)
}

extension UInt: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(
        name: "UInt", signed: false, bits: UInt.bitWidth
    )
}

extension UInt8: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "UInt8", signed: false, bits: 8)
}

extension UInt16: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "UInt16", signed: false, bits: 16)
}

extension UInt32: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "UInt32", signed: false, bits: 32)
}

extension UInt64: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .integer(name: "UInt64", signed: false, bits: 64)
}

internal protocol BindingOptionalShape {
    static var wrappedBindingType: Any.Type { get }
}

extension Optional: BindingOptionalShape {
    internal static var wrappedBindingType: Any.Type { Wrapped.self }
}

internal protocol BindingArrayShape {
    static var elementBindingType: Any.Type { get }
}

extension Array: BindingArrayShape {
    internal static var elementBindingType: Any.Type { Element.self }
}

internal protocol BindingDictionaryShape {
    static var keyBindingType: Any.Type { get }
    static var valueBindingType: Any.Type { get }
}

extension Dictionary: BindingDictionaryShape {
    internal static var keyBindingType: Any.Type { Key.self }
    internal static var valueBindingType: Any.Type { Value.self }
}

extension Data: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .data
}

extension Date: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .date
}

extension URL: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .url
}

extension JavaScriptBigInt: BindingTypeShapeProviding {
    internal static let bindingTypeShape: BindingTypeShape = .bigInt
}

internal func bindingTypeShape<T>(for type: T.Type) -> BindingTypeShape {
    bindingTypeShape(forAny: type)
}

private func bindingTypeShape(forAny type: Any.Type) -> BindingTypeShape {
    if let provider = type as? any BindingTypeShapeProviding.Type {
        return provider.bindingTypeShape
    }
    if let optional = type as? any BindingOptionalShape.Type {
        return .optional(bindingTypeShape(forAny: optional.wrappedBindingType))
    }
    if let array = type as? any BindingArrayShape.Type {
        return .array(bindingTypeShape(forAny: array.elementBindingType))
    }
    if let dictionary = type as? any BindingDictionaryShape.Type,
       ObjectIdentifier(dictionary.keyBindingType) == ObjectIdentifier(String.self) {
        return .dictionary(bindingTypeShape(forAny: dictionary.valueBindingType))
    }
    let schema = (type as? any TypeScriptSchemaProviding.Type)?.typeScriptSchema
    return .codable(swiftName: String(reflecting: type), schema: schema)
}

internal func bindingParameterShapes<each Parameter>(
    _ types: repeat (each Parameter).Type
) -> [BindingTypeShape] {
    var shapes: [BindingTypeShape] = []
    for type in repeat each types {
        shapes.append(bindingTypeShape(for: type))
    }
    return shapes
}

internal func bindingTypeShape(for value: JavaScriptValue) -> BindingTypeShape {
    switch value.storage {
    case .undefined:
        return .undefined
    case .null:
        return .null
    case .boolean:
        return .boolean
    case .number:
        return .floatingPoint("Double")
    case .string:
        return .string
    case .bigInt:
        return .bigInt
    case .reference:
        return .unknown
    }
}
