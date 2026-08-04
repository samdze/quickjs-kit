import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

struct ParsedDocumentation {
    var summary = ""
    var remarks: String?
    var parameters: [String: String] = [:]
    var duplicateParameters: Set<String> = []
    var returns: String?
    var throwsDescription: String?
    var examples: [String] = []
    var seeAlso: [String] = []
    var deprecated: String?
    var defaultValue: String?

    var declarationExpression: String {
        guard !summary.isEmpty else { return "nil" }
        var arguments = ["summary: \(swiftLiteral(summary))"]
        if let remarks { arguments.append("remarks: \(swiftLiteral(remarks))") }
        appendCommonArguments(to: &arguments)
        return ".init(\(arguments.joined(separator: ", ")))"
    }

    func functionExpression(parameterNames: [String], isThrowing: Bool) -> String {
        guard !summary.isEmpty else { return "nil" }
        var arguments = ["summary: \(swiftLiteral(summary))"]
        if let remarks { arguments.append("remarks: \(swiftLiteral(remarks))") }
        let documented = parameterNames.compactMap { name -> String? in
            guard let value = parameters[name] else { return nil }
            return "\(swiftLiteral(name)): \(swiftLiteral(value))"
        }
        if !documented.isEmpty {
            arguments.append("parameters: [\(documented.joined(separator: ", "))]")
        }
        if let returns { arguments.append("returns: \(swiftLiteral(returns))") }
        if let throwsDescription {
            arguments.append(
                "errors: [.init(description: \(swiftLiteral(throwsDescription)))]"
            )
        } else if isThrowing {
            arguments.append("errors: []")
        }
        appendCommonArguments(to: &arguments)
        return ".init(\(arguments.joined(separator: ", ")))"
    }

    private func appendCommonArguments(to arguments: inout [String]) {
        if !examples.isEmpty {
            let values = examples.map {
                ".init(body: \(swiftLiteral($0)))"
            }.joined(separator: ", ")
            arguments.append("examples: [\(values)]")
        }
        if !seeAlso.isEmpty {
            arguments.append(
                "seeAlso: [\(seeAlso.map(swiftLiteral).joined(separator: ", "))]"
            )
        }
        if let deprecated {
            arguments.append("deprecated: \(swiftLiteral(deprecated))")
        }
    }
}

func documentation(of declaration: some SyntaxProtocol) -> ParsedDocumentation {
    let raw = declaration.leadingTrivia.description
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map {
        line -> String in
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("///") { text.removeFirst(3) }
        else if text.hasPrefix("/**") { text.removeFirst(3) }
        else if text.hasPrefix("/*!") { text.removeFirst(3) }
        else if text.hasPrefix("*") { text.removeFirst() }
        if text.hasSuffix("*/") { text.removeLast(2) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var result = ParsedDocumentation()
    var prose: [String] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        if line == "- Parameters:" {
            index += 1
            while index < lines.count,
                  lines[index].hasPrefix("- "),
                  let colon = lines[index].firstIndex(of: ":") {
                let entry = lines[index]
                let name = String(entry[entry.index(entry.startIndex, offsetBy: 2)..<colon])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(entry[entry.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                if result.parameters.updateValue(value, forKey: name) != nil {
                    result.duplicateParameters.insert(name)
                }
                index += 1
            }
            continue
        } else if line.hasPrefix("- Parameter "),
           let colon = line.firstIndex(of: ":") {
            let start = line.index(line.startIndex, offsetBy: 12)
            let name = String(line[start..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if result.parameters.updateValue(value, forKey: name) != nil {
                result.duplicateParameters.insert(name)
            }
        } else if line.hasPrefix("- Returns:") {
            result.returns = String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("- Throws:") {
            result.throwsDescription = String(line.dropFirst(9))
                .trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("- Deprecated:") {
            result.deprecated = String(line.dropFirst(13))
                .trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("- Default:") {
            result.defaultValue = String(line.dropFirst(10))
                .trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("- See Also:") {
            result.seeAlso.append(
                String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
            )
        } else if line.hasPrefix("- Example:") {
            result.examples.append(
                String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces)
            )
        } else if line == "## Example" || line == "### Example" {
            var example: [String] = []
            index += 1
            while index < lines.count, !lines[index].hasPrefix("##") {
                example.append(lines[index])
                index += 1
            }
            let body = example.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { result.examples.append(body) }
            continue
        } else if line == "## See Also" || line == "### See Also" {
            index += 1
            while index < lines.count, !lines[index].hasPrefix("##") {
                let reference = lines[index]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                if !reference.isEmpty { result.seeAlso.append(reference) }
                index += 1
            }
            continue
        } else {
            prose.append(line)
        }
        index += 1
    }
    while prose.first?.isEmpty == true { prose.removeFirst() }
    while prose.last?.isEmpty == true { prose.removeLast() }
    if let blank = prose.firstIndex(where: { $0.isEmpty }) {
        result.summary = prose[..<blank].joined(separator: " ")
        let remainder = prose[prose.index(after: blank)...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result.remarks = remainder.isEmpty ? nil : remainder
    } else {
        result.summary = prose.joined(separator: " ")
    }
    if result.deprecated == nil {
        result.deprecated = availabilityDeprecation(of: declaration)
    }
    return result
}

private func availabilityDeprecation(
    of declaration: some SyntaxProtocol
) -> String? {
    let attributes: AttributeListSyntax?
    if let value = declaration.as(ClassDeclSyntax.self) { attributes = value.attributes }
    else if let value = declaration.as(ActorDeclSyntax.self) { attributes = value.attributes }
    else if let value = declaration.as(StructDeclSyntax.self) { attributes = value.attributes }
    else if let value = declaration.as(EnumDeclSyntax.self) { attributes = value.attributes }
    else if let value = declaration.as(EnumCaseDeclSyntax.self) { attributes = value.attributes }
    else if let value = declaration.as(FunctionDeclSyntax.self) { attributes = value.attributes }
    else if let value = declaration.as(VariableDeclSyntax.self) { attributes = value.attributes }
    else { attributes = nil }

    guard let attributes else { return nil }
    for element in attributes {
        guard case let .attribute(attribute) = element,
              attributeName(attribute).split(separator: ".").last == "available" else {
            continue
        }
        let text = attribute.trimmedDescription
        guard text.contains("deprecated") else { continue }
        if let messageRange = text.range(of: "message:"),
           let firstQuote = text[messageRange.upperBound...].firstIndex(of: "\""),
           let lastQuote = text[text.index(after: firstQuote)...].firstIndex(of: "\"") {
            return String(text[text.index(after: firstQuote)..<lastQuote])
        }
        return "This declaration is deprecated."
    }
    return nil
}

func swiftLiteral(_ value: String) -> String {
    String(reflecting: value)
}

func signedIntegerLiteral(_ expression: ExprSyntax) -> Int64? {
    var text = expression.trimmedDescription.replacingOccurrences(of: "_", with: "")
    var isNegative = false
    if text.hasPrefix("-") {
        isNegative = true
        text.removeFirst()
    } else if text.hasPrefix("+") {
        text.removeFirst()
    }
    let radix: Int
    if text.hasPrefix("0x") || text.hasPrefix("0X") {
        radix = 16
        text.removeFirst(2)
    } else if text.hasPrefix("0o") || text.hasPrefix("0O") {
        radix = 8
        text.removeFirst(2)
    } else if text.hasPrefix("0b") || text.hasPrefix("0B") {
        radix = 2
        text.removeFirst(2)
    } else {
        radix = 10
    }
    guard let magnitude = UInt64(text, radix: radix) else { return nil }
    if isNegative {
        if magnitude == UInt64(Int64.max) + 1 { return Int64.min }
        guard magnitude <= UInt64(Int64.max) else { return nil }
        return -Int64(magnitude)
    }
    return Int64(exactly: magnitude)
}

func sourceLocationExpression(
    of declaration: some SyntaxProtocol,
    in context: some MacroExpansionContext
) -> String {
    guard let location = context.location(of: declaration) else { return "nil" }
    return ".init(fileID: \(location.file), line: \(location.line), column: \(location.column))"
}

func attributeName(_ attribute: AttributeSyntax) -> String {
    attribute.attributeName.trimmedDescription
}

func hasAttribute(_ name: String, on attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard case let .attribute(attribute) = element else { return false }
        return attributeName(attribute).split(separator: ".").last == Substring(name)
    }
}

func renamedJavaScriptName(in attributes: AttributeListSyntax) -> String? {
    for element in attributes {
        guard case let .attribute(attribute) = element,
              attributeName(attribute).split(separator: ".").last == "JavaScriptName",
              case let .argumentList(arguments) = attribute.arguments,
              let first = arguments.first,
              let literal = first.expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              case let .stringSegment(segment) = literal.segments.first else {
            continue
        }
        return segment.content.text
    }
    return nil
}

func isExcluded(_ modifiers: DeclModifierListSyntax) -> Bool {
    modifiers.contains {
        ["private", "fileprivate", "static", "class"].contains($0.name.text)
    }
}

func declarationName(_ declaration: some DeclGroupSyntax) throws -> String {
    if let value = declaration.as(ClassDeclSyntax.self) { return value.name.text }
    if let value = declaration.as(ActorDeclSyntax.self) { return value.name.text }
    if let value = declaration.as(StructDeclSyntax.self) { return value.name.text }
    if let value = declaration.as(EnumDeclSyntax.self) { return value.name.text }
    if let value = declaration.as(ProtocolDeclSyntax.self) {
        throw macroFailure(.unsupportedDeclaration, at: value.name)
    }
    throw macroFailure(.unsupportedDeclaration, at: declaration)
}

struct ResolvedTypeScriptType {
    let expression: String
    let isOptional: Bool
    let dependencies: Set<String>
}

func resolveTypeScriptType(
    _ type: TypeSyntax
) throws -> ResolvedTypeScriptType {
    if let optional = type.as(OptionalTypeSyntax.self) {
        let wrapped = try resolveTypeScriptType(optional.wrappedType)
        return .init(
            expression: ".union([\(wrapped.expression), .null])",
            isOptional: true,
            dependencies: wrapped.dependencies
        )
    }
    if let array = type.as(ArrayTypeSyntax.self) {
        let element = try resolveTypeScriptType(array.element)
        return .init(
            expression: ".array(\(element.expression))",
            isOptional: false,
            dependencies: element.dependencies
        )
    }
    if let dictionary = type.as(DictionaryTypeSyntax.self) {
        guard unqualifiedTypeName(dictionary.key) == "String" else {
            throw macroFailure(
                .unsupportedValueType(type.trimmedDescription),
                at: dictionary.key
            )
        }
        let value = try resolveTypeScriptType(dictionary.value)
        return .init(
            expression: ".record(\(value.expression))",
            isOptional: false,
            dependencies: value.dependencies
        )
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return try resolveIdentifierType(identifier, original: type)
    }
    if let member = type.as(MemberTypeSyntax.self) {
        guard member.genericArgumentClause == nil else {
            throw macroFailure(
                .unsupportedValueType(type.trimmedDescription),
                at: type
            )
        }
        return resolveNamedType(
            name: member.name.text,
            qualifiedName: type.trimmedDescription
        )
    }
    throw macroFailure(
        .unsupportedValueType(type.trimmedDescription),
        at: type
    )
}

private func resolveIdentifierType(
    _ identifier: IdentifierTypeSyntax,
    original: TypeSyntax
) throws -> ResolvedTypeScriptType {
    let name = identifier.name.text
    if let arguments = identifier.genericArgumentClause?.arguments {
        let values = Array(arguments)
        switch name {
        case "Optional" where values.count == 1:
            let wrapped = try resolveTypeScriptType(
                try genericTypeArgument(values[0], original: original)
            )
            return .init(
                expression: ".union([\(wrapped.expression), .null])",
                isOptional: true,
                dependencies: wrapped.dependencies
            )
        case "Array" where values.count == 1:
            let element = try resolveTypeScriptType(
                try genericTypeArgument(values[0], original: original)
            )
            return .init(
                expression: ".array(\(element.expression))",
                isOptional: false,
                dependencies: element.dependencies
            )
        case "Dictionary" where values.count == 2:
            let key = try genericTypeArgument(values[0], original: original)
            guard unqualifiedTypeName(key) == "String" else {
                throw macroFailure(
                    .unsupportedValueType(original.trimmedDescription),
                    at: key
                )
            }
            let value = try resolveTypeScriptType(
                try genericTypeArgument(values[1], original: original)
            )
            return .init(
                expression: ".record(\(value.expression))",
                isOptional: false,
                dependencies: value.dependencies
            )
        default:
            throw macroFailure(
                .unsupportedValueType(original.trimmedDescription),
                at: original
            )
        }
    }
    return resolveNamedType(name: name, qualifiedName: name)
}

private func genericTypeArgument(
    _ argument: GenericArgumentSyntax,
    original: TypeSyntax
) throws -> TypeSyntax {
    guard case let .type(type) = argument.argument else {
        throw macroFailure(
            .unsupportedValueType(original.trimmedDescription),
            at: argument
        )
    }
    return type
}

private func resolveNamedType(
    name: String,
    qualifiedName: String
) -> ResolvedTypeScriptType {
    let simple: [String: String] = [
        "Bool": ".boolean", "String": ".string", "URL": ".string",
        "Float": ".number", "Double": ".number",
        "Int8": ".number", "UInt8": ".number",
        "Int16": ".number", "UInt16": ".number",
        "Int32": ".number", "UInt32": ".number",
        "Int": ".union([.number, .bigint])",
        "UInt": ".union([.number, .bigint])",
        "Int64": ".union([.number, .bigint])",
        "UInt64": ".union([.number, .bigint])",
        "Data": ".uint8Array", "Date": ".date",
        "JavaScriptBigInt": ".bigint",
    ]
    if let value = simple[name] {
        return .init(
            expression: value,
            isOptional: false,
            dependencies: []
        )
    }
    return .init(
        expression: ".named(\(swiftLiteral(name)))",
        isOptional: false,
        dependencies: [qualifiedName]
    )
}

private func unqualifiedTypeName(_ type: TypeSyntax) -> String? {
    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.genericArgumentClause == nil {
        return identifier.name.text
    }
    if let member = type.as(MemberTypeSyntax.self),
       member.genericArgumentClause == nil {
        return member.name.text
    }
    return nil
}

func isValidJavaScriptIdentifier(_ name: String) -> Bool {
    guard !name.isEmpty else { return false }
    let scalars = Array(name.unicodeScalars)
    guard let first = scalars.first,
          isJavaScriptIdentifierStart(first) else {
        return false
    }
    return scalars.dropFirst().allSatisfy(isJavaScriptIdentifierContinue)
        && !javaScriptReservedIdentifiers.contains(name)
}

private func isJavaScriptIdentifierStart(_ scalar: UnicodeScalar) -> Bool {
    scalar == "_" || scalar == "$"
        || ("a"..."z").contains(Character(String(scalar)))
        || ("A"..."Z").contains(Character(String(scalar)))
}

private func isJavaScriptIdentifierContinue(_ scalar: UnicodeScalar) -> Bool {
    isJavaScriptIdentifierStart(scalar)
        || ("0"..."9").contains(Character(String(scalar)))
}

private let javaScriptReservedIdentifiers: Set<String> = [
    "await", "break", "case", "catch", "class", "const", "continue",
    "debugger", "default", "delete", "do", "else", "enum", "export",
    "extends", "false", "finally", "for", "function", "if", "import",
    "in", "instanceof", "let", "new", "null", "return", "static",
    "super", "switch", "this", "throw", "true", "try", "typeof",
    "var", "void", "while", "with", "yield", "implements", "interface",
    "package", "private", "protected", "public",
]

func hasUnsupportedParameterFeatures(_ parameter: FunctionParameterSyntax) -> Bool {
    if parameter.defaultValue != nil || parameter.ellipsis != nil
        || !parameter.attributes.isEmpty || !parameter.modifiers.isEmpty {
        return true
    }
    guard let attributed = parameter.type.as(AttributedTypeSyntax.self) else {
        return false
    }
    return !attributed.attributes.isEmpty
        || !attributed.specifiers.isEmpty
        || !attributed.lateSpecifiers.isEmpty
}
