import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

struct QuickJSKitMacroError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

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
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map {
        line -> String in
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("///") { text.removeFirst(3) }
        else if text.hasPrefix("/**") { text.removeFirst(3) }
        else if text.hasPrefix("/*!") { text.removeFirst(3) }
        else if text.hasPrefix("*") { text.removeFirst() }
        if text.hasSuffix("*/") { text.removeLast(2) }
        return text.trimmingCharacters(in: .whitespaces)
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
    throw QuickJSKitMacroError("This macro does not support this declaration kind.")
}

func typeScriptTypeExpression(_ source: String) -> (type: String, optional: Bool, dependency: String?) {
    let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasSuffix("?") {
        let wrapped = String(text.dropLast())
        let resolved = typeScriptTypeExpression(wrapped)
        return (".union([\(resolved.type), .null])", true, resolved.dependency)
    }
    if text.hasPrefix("[") && text.hasSuffix("]") {
        let inner = String(text.dropFirst().dropLast())
        if let colon = inner.firstIndex(of: ":"),
           inner[..<colon].trimmingCharacters(in: .whitespaces) == "String" {
            let value = String(inner[inner.index(after: colon)...])
            let resolved = typeScriptTypeExpression(value)
            return (".record(\(resolved.type))", false, resolved.dependency)
        }
        let resolved = typeScriptTypeExpression(inner)
        return (".array(\(resolved.type))", false, resolved.dependency)
    }
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
    if let value = simple[text] { return (value, false, nil) }
    let name = text.split(separator: ".").last.map(String.init) ?? text
    return (".named(\(swiftLiteral(name)))", false, text)
}
