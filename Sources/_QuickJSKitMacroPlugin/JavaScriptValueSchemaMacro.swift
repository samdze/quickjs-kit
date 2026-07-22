import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum JavaScriptValueSchemaMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let name = try declarationName(declaration)
        let scope = scopeExpression(node)
        if let enumeration = declaration.as(EnumDeclSyntax.self) {
            return [
                try enumExtension(
                    enumeration,
                    type: type,
                    name: name,
                    scope: scope,
                    context: context
                ),
            ]
        }
        if let classDeclaration = declaration.as(ClassDeclSyntax.self),
           !classDeclaration.modifiers.contains(where: { $0.name.text == "final" }) {
            throw QuickJSKitMacroError("@JavaScriptExport requires classes to be final.")
        }
        guard declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) else {
            throw QuickJSKitMacroError(
                "@JavaScriptExport supports Codable structs and raw String or Int enums as value types."
            )
        }
        let properties = try modelProperties(declaration, context: context)
        let docs = documentation(of: declaration).declarationExpression
        let propertySource = properties.map(\.expression).joined(separator: ",\n            ")
        let dependencies = Array(Set(properties.compactMap(\.dependency).filter { $0 != name }))
            .sorted()
            .map { "\($0).self" }
            .joined(separator: ", ")
        return [try ExtensionDeclSyntax("""
        extension \(type.trimmed): TypeScriptSchemaProviding {
            public static var typeScriptSchema: TypeScriptSchema {
                .interface(
                    \(literal: name),
                    scope: \(raw: scope),
                    documentation: \(raw: docs),
                    sourceLocation: \(raw: sourceLocationExpression(of: declaration, in: context)),
                    properties: [
                        \(raw: propertySource)
                    ]
                )
            }

            public static var typeScriptSchemaDependencies: [any TypeScriptSchemaProviding.Type] {
                [\(raw: dependencies)]
            }
        }
        """)]
    }

    private struct ModelProperty {
        let expression: String
        let dependency: String?
    }

    private static func modelProperties(
        _ declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) throws -> [ModelProperty] {
        let codingKeys = codingKeyNames(in: declaration)
        var result: [ModelProperty] = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !isExcluded(variable.modifiers) else { continue }
            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let annotation = binding.typeAnnotation else { continue }
                let swiftName = pattern.identifier.text
                if let codingKeys, codingKeys[swiftName] == nil { continue }
                let encodedName = codingKeys?[swiftName] ?? swiftName
                let resolved = typeScriptTypeExpression(annotation.type.trimmedDescription)
                let parsedDocs = documentation(of: variable)
                let docs = parsedDocs.declarationExpression
                let defaultValue = parsedDocs.defaultValue.map(swiftLiteral) ?? "nil"
                result.append(
                    ModelProperty(
                        expression: ".init(\(swiftLiteral(encodedName)), type: \(resolved.type), isOptional: \(resolved.optional), documentation: \(docs), defaultValue: \(defaultValue), sourceLocation: \(sourceLocationExpression(of: binding, in: context)))",
                        dependency: resolved.dependency
                    )
                )
            }
        }
        return result
    }

    private static func codingKeyNames(
        in declaration: some DeclGroupSyntax
    ) -> [String: String]? {
        guard let codingKeys = declaration.memberBlock.members.compactMap({
            $0.decl.as(EnumDeclSyntax.self)
        }).first(where: { $0.name.text == "CodingKeys" }) else {
            return nil
        }
        var names: [String: String] = [:]
        for member in codingKeys.memberBlock.members {
            guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in cases.elements {
                let swiftName = element.name.text
                if let raw = element.rawValue?.value.as(StringLiteralExprSyntax.self),
                   raw.segments.count == 1,
                   case let .stringSegment(segment) = raw.segments.first {
                    names[swiftName] = segment.content.text
                } else {
                    names[swiftName] = swiftName
                }
            }
        }
        return names
    }

    private static func enumExtension(
        _ declaration: EnumDeclSyntax,
        type: some TypeSyntaxProtocol,
        name: String,
        scope: String,
        context: some MacroExpansionContext
    ) throws -> ExtensionDeclSyntax {
        let inherited = declaration.inheritanceClause?.inheritedTypes.map {
            $0.type.trimmedDescription
        } ?? []
        let isString = inherited.contains("String")
        let isInteger = inherited.contains("Int")
        guard isString || isInteger else {
            throw QuickJSKitMacroError(
                "@JavaScriptExport enums require a raw String or Int representation."
            )
        }
        var nextInteger: Int64? = 0
        var cases: [String] = []
        for member in declaration.memberBlock.members {
            guard let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) else {
                continue
            }
            for element in caseDeclaration.elements {
                let caseName = element.name.text
                let value: String
                if isString {
                    if let literal = element.rawValue?.value.as(StringLiteralExprSyntax.self),
                       literal.segments.count == 1,
                       case let .stringSegment(segment) = literal.segments.first {
                        value = ".string(\(swiftLiteral(segment.content.text)))"
                    } else {
                        value = ".string(\(swiftLiteral(caseName)))"
                    }
                } else if let literal = element.rawValue?.value,
                          let integer = signedIntegerLiteral(literal) {
                    value = ".integer(\(integer))"
                    nextInteger = integer == .max ? nil : integer + 1
                } else if element.rawValue == nil, let integer = nextInteger {
                    value = ".integer(\(integer))"
                    nextInteger = integer == .max ? nil : integer + 1
                } else {
                    throw QuickJSKitMacroError(
                        "Raw Int enum values used by @JavaScriptExport must be integer literals within Int64, and implicit values cannot follow Int64.max."
                    )
                }
                let docs = documentation(of: caseDeclaration).declarationExpression
                cases.append(
                    ".init(\(swiftLiteral(caseName)), value: \(value), documentation: \(docs), sourceLocation: \(sourceLocationExpression(of: element, in: context)))"
                )
            }
        }
        let docs = documentation(of: declaration).declarationExpression
        let caseSource = cases.joined(separator: ",\n            ")
        return try ExtensionDeclSyntax("""
        extension \(type.trimmed): TypeScriptSchemaProviding {
            public static var typeScriptSchema: TypeScriptSchema {
                .enumeration(
                    \(literal: name),
                    scope: \(raw: scope),
                    documentation: \(raw: docs),
                    sourceLocation: \(raw: sourceLocationExpression(of: declaration, in: context)),
                    cases: [
                        \(raw: caseSource)
                    ]
                )
            }
        }
        """)
    }

    private static func scopeExpression(_ node: AttributeSyntax) -> String {
        guard case let .argumentList(arguments) = node.arguments,
              let argument = arguments.first else { return "nil" }
        return argument.expression.trimmedDescription
    }
}
