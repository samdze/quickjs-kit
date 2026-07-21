/// Supplies deterministic TypeScript metadata for a Swift model.
///
/// QuickJSKit discovers this conformance when the model appears in a typed
/// binding or exported value. Future macros can synthesize the same metadata
/// without creating a separate declaration system.
public protocol TypeScriptSchemaProviding {
    /// The TypeScript schema representing this Swift type.
    static var typeScriptSchema: TypeScriptSchema { get }
}

/// A complete TypeScript representation for one Swift type.
///
/// A schema has one primary type and may carry several related definitions.
/// Keeping references and definitions separate permits recursive and mutually
/// recursive interfaces without recursive Swift storage.
public struct TypeScriptSchema: Sendable, Hashable {
    /// The TypeScript type used at binding call sites.
    public let type: TypeScriptType

    /// Named declarations required by ``type``.
    public let definitions: [TypeScriptDefinition]

    /// Creates a schema from a primary type and its named declarations.
    public init(
        type: TypeScriptType,
        definitions: [TypeScriptDefinition]
    ) {
        self.type = type
        self.definitions = definitions
    }

    /// Creates a schema containing one interface declaration.
    public static func interface(
        _ name: String,
        documentation: String? = nil,
        properties: [TypeScriptProperty]
    ) -> Self {
        Self(
            type: .named(name),
            definitions: [
                .interface(
                    name: name,
                    documentation: documentation,
                    properties: properties
                ),
            ]
        )
    }

    /// Creates a schema containing one named type alias.
    public static func alias(
        _ name: String,
        to type: TypeScriptType,
        documentation: String? = nil
    ) -> Self {
        Self(
            type: .named(name),
            definitions: [
                .alias(name: name, documentation: documentation, type: type),
            ]
        )
    }

    /// Creates a schema containing an enum-style literal union.
    ///
    /// The declaration is a type alias rather than a TypeScript runtime enum,
    /// matching Codable values that do not export a JavaScript enum object.
    public static func enumeration(
        _ name: String,
        documentation: String? = nil,
        cases: [TypeScriptEnumCase]
    ) -> Self {
        Self(
            type: .named(name),
            definitions: [
                .enumeration(
                    name: name,
                    documentation: documentation,
                    cases: cases
                ),
            ]
        )
    }
}

/// A TypeScript type expression supported by QuickJSKit schemas.
public indirect enum TypeScriptType: Sendable, Hashable {
    /// TypeScript `boolean`.
    case boolean
    /// TypeScript `string`.
    case string
    /// TypeScript `number`.
    case number
    /// TypeScript `bigint`.
    case bigint
    /// TypeScript `null`.
    case null
    /// TypeScript `undefined`.
    case undefined
    /// TypeScript `unknown`.
    case unknown
    /// The standard JavaScript `Date` object.
    case date
    /// The standard JavaScript `Uint8Array` object.
    case uint8Array
    /// A named type declared by a schema definition.
    case named(String)
    /// A mutable JavaScript array.
    case array(TypeScriptType)
    /// A string-keyed JavaScript object.
    case record(TypeScriptType)
    /// A union of one or more TypeScript types.
    case union([TypeScriptType])
    /// A string or integer literal type.
    case literal(TypeScriptLiteral)
}

/// A named TypeScript declaration carried by a schema.
public enum TypeScriptDefinition: Sendable, Hashable {
    /// A structural interface.
    case interface(
        name: String,
        documentation: String?,
        properties: [TypeScriptProperty]
    )

    /// A named type alias.
    case alias(
        name: String,
        documentation: String?,
        type: TypeScriptType
    )

    /// A named string or integer literal union.
    case enumeration(
        name: String,
        documentation: String?,
        cases: [TypeScriptEnumCase]
    )
}

/// A property in a TypeScript interface.
public struct TypeScriptProperty: Sendable, Hashable {
    /// The JavaScript property name.
    public let name: String

    /// The property's TypeScript type.
    public let type: TypeScriptType

    /// Whether callers may omit this property.
    public let isOptional: Bool

    /// Whether TypeScript should prevent assignment to this property.
    public let isReadonly: Bool

    /// Documentation rendered as JSDoc.
    public let documentation: String?

    /// Creates an interface property.
    public init(
        _ name: String,
        type: TypeScriptType,
        isOptional: Bool = false,
        isReadonly: Bool = false,
        documentation: String? = nil
    ) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.isReadonly = isReadonly
        self.documentation = documentation
    }
}

/// One documented value in an enum-style literal union.
public struct TypeScriptEnumCase: Sendable, Hashable {
    /// The Swift-facing case name used in generated documentation.
    public let name: String

    /// The encoded JavaScript literal.
    public let value: TypeScriptLiteral

    /// Documentation rendered beside this literal.
    public let documentation: String?

    /// Creates a literal-union case.
    public init(
        _ name: String,
        value: TypeScriptLiteral,
        documentation: String? = nil
    ) {
        self.name = name
        self.value = value
        self.documentation = documentation
    }
}

/// A literal value supported in generated TypeScript types.
public enum TypeScriptLiteral: Sendable, Hashable {
    /// A string literal.
    case string(String)
    /// A signed integer literal.
    case integer(Int64)
}
