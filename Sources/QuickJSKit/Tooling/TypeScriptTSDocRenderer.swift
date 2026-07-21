internal import Foundation

internal struct TypeScriptTSDocRenderer {
    internal let completeness: DocumentationCompleteness

    private var requiresCompleteDocumentation: Bool {
        completeness == .requireComplete
    }

    internal func definitionDocumentation(
        _ definition: ResolvedTypeScriptDefinition
    ) throws -> String? {
        try validateDocumentation(
            definition.documentation,
            at: "TypeScript definition '\(definition.key.name)'"
        )
        guard case let .enumeration(cases) = definition.kind else {
            return jsDoc(definition.documentation)
        }
        let documentedCases = try cases.compactMap { enumCase -> String? in
            try validateDocumentation(
                enumCase.documentation,
                at: "TypeScript enum case '\(definition.key.name).\(enumCase.name)'"
            )
            guard let documentation = enumCase.documentation,
                  !normalized(documentation.summary).isEmpty else { return nil }
            var lines = [
                "- `\(enumCase.name)` (`\(renderTypeScriptLiteral(enumCase.value))`): \(documentation.summary)",
            ]
            if let remarks = documentation.remarks, !normalized(remarks).isEmpty {
                lines.append("  Remarks: \(remarks)")
            }
            for example in documentation.examples {
                let title = example.title.map { " \($0)" } ?? ""
                lines.append("  Example\(title):\n\(example.body)")
            }
            for reference in documentation.seeAlso {
                lines.append("  See: \(reference)")
            }
            if let deprecated = documentation.deprecated,
               !normalized(deprecated).isEmpty {
                lines.append("  Deprecated: \(deprecated)")
            }
            return lines.joined(separator: "\n")
        }
        return jsDoc(
            definition.documentation,
            additionalRemarks: documentedCases.isEmpty
                ? []
                : ["Cases:\n" + documentedCases.joined(separator: "\n")]
        )
    }

    internal func propertyDocumentation(
        _ property: ResolvedTypeScriptProperty,
        definition: ResolvedTypeScriptDefinition
    ) throws -> String? {
        try validateDocumentation(
            property.documentation,
            at: "TypeScript property '\(definition.key.name).\(property.name)'"
        )
        return jsDoc(property.documentation, defaultValue: property.defaultValue)
    }

    internal func functionDocumentation(
        _ function: EnvironmentFunctionDescription,
        at location: String
    ) throws -> String? {
        if let message = TypeScriptDocumentationValidation.message(
            for: function.documentation,
            parameterNames: function.parameters.map(\.name)
        ) {
            throw TypeScriptToolingError("Invalid documentation for \(location): \(message)")
        }

        if requiresCompleteDocumentation {
            guard let documentation = function.documentation,
                  !normalized(documentation.summary).isEmpty else {
                throw missingDocumentation("summary", at: location)
            }
            for parameter in function.parameters {
                guard let value = documentation.parameters[parameter.name],
                      !normalized(value).isEmpty else {
                    throw missingDocumentation("parameter '\(parameter.name)'", at: location)
                }
            }
            if function.result != .void,
               normalized(documentation.returns ?? "").isEmpty {
                throw missingDocumentation("return value", at: location)
            }
            if function.effects.isThrowing,
               !documentation.errors.contains(where: {
                   !normalized($0.description).isEmpty
               }) {
                throw missingDocumentation("thrown error", at: location)
            }
        }

        guard let documentation = function.documentation else {
            if function.effects.isThrowing {
                return renderJSDoc(sections: [["@throws When the Swift operation fails."]])
            }
            return nil
        }

        var sections: [[String]] = []
        appendText(documentation.summary, to: &sections)
        appendBlockTag("@remarks", documentation.remarks, to: &sections)
        for parameter in function.parameters {
            guard let value = documentation.parameters[parameter.name] else { continue }
            appendTaggedText("@param \(parameter.name) -", value, to: &sections)
        }
        appendTaggedText("@returns", documentation.returns, to: &sections)
        if documentation.errors.isEmpty, function.effects.isThrowing {
            sections.append(["@throws When the Swift operation fails."])
        } else {
            for error in documentation.errors {
                let tag = error.reference.map { "@throws {@link \($0)}" } ?? "@throws"
                appendBlockTag(tag, error.description, to: &sections)
            }
        }
        appendExamples(documentation.examples, to: &sections)
        for reference in documentation.seeAlso {
            appendTaggedText("@see", reference, to: &sections)
        }
        appendTaggedText("@deprecated", documentation.deprecated, to: &sections)
        return renderJSDoc(sections: sections)
    }

    internal func documentation(
        _ documentation: TypeScriptDocumentation?,
        at location: String,
        defaultValue: String? = nil
    ) throws -> String? {
        try validateDocumentation(documentation, at: location)
        return jsDoc(documentation, defaultValue: defaultValue)
    }

    private func validateDocumentation(
        _ documentation: TypeScriptDocumentation?,
        at location: String
    ) throws {
        if let message = TypeScriptDocumentationValidation.message(for: documentation) {
            throw TypeScriptToolingError("Invalid documentation for \(location): \(message)")
        }
        if requiresCompleteDocumentation,
           normalized(documentation?.summary ?? "").isEmpty {
            throw missingDocumentation("summary", at: location)
        }
    }

    private func missingDocumentation(_ field: String, at location: String) -> TypeScriptToolingError {
        TypeScriptToolingError("Complete TSDoc requires a \(field) for \(location).")
    }

    private func jsDoc(
        _ documentation: TypeScriptDocumentation?,
        defaultValue: String? = nil,
        additionalRemarks: [String] = []
    ) -> String? {
        guard documentation != nil || defaultValue != nil || !additionalRemarks.isEmpty else {
            return nil
        }
        var sections: [[String]] = []
        if let documentation {
            appendText(documentation.summary, to: &sections)
            appendBlockTag("@remarks", documentation.remarks, to: &sections)
        }
        for remarks in additionalRemarks {
            appendBlockTag("@remarks", remarks, to: &sections)
        }
        appendTaggedText("@defaultValue", defaultValue, to: &sections)
        if let documentation {
            appendExamples(documentation.examples, to: &sections)
            for reference in documentation.seeAlso {
                appendTaggedText("@see", reference, to: &sections)
            }
            appendTaggedText("@deprecated", documentation.deprecated, to: &sections)
        }
        return renderJSDoc(sections: sections)
    }

    private func appendText(_ value: String, to sections: inout [[String]]) {
        let lines = documentationLines(value)
        if !lines.isEmpty { sections.append(lines) }
    }

    private func appendTaggedText(
        _ tag: String,
        _ value: String?,
        to sections: inout [[String]]
    ) {
        guard let value else { return }
        var lines = documentationLines(value)
        guard !lines.isEmpty else { return }
        lines[0] = "\(tag) \(lines[0])"
        sections.append(lines)
    }

    private func appendBlockTag(
        _ tag: String,
        _ value: String?,
        to sections: inout [[String]]
    ) {
        guard let value else { return }
        let lines = documentationLines(value)
        guard !lines.isEmpty else { return }
        sections.append([tag] + lines)
    }

    private func appendExamples(
        _ examples: [TypeScriptDocumentation.Example],
        to sections: inout [[String]]
    ) {
        for example in examples {
            let tag = example.title.map { "@example \(sanitizeLine($0))" } ?? "@example"
            var lines = documentationLines(example.body)
            if lines.isEmpty {
                sections.append([tag])
            } else {
                lines.insert(tag, at: 0)
                sections.append(lines)
            }
        }
    }

    private func renderJSDoc(sections: [[String]]) -> String? {
        let sections = sections.filter { !$0.isEmpty }
        guard !sections.isEmpty else { return nil }
        if sections.count == 1, sections[0].count == 1,
           !sections[0][0].hasPrefix("@") {
            return "/** \(sections[0][0]) */"
        }
        var lines = ["/**"]
        for (index, section) in sections.enumerated() {
            if index > 0 { lines.append(" *") }
            lines.append(contentsOf: section.map { $0.isEmpty ? " *" : " * \($0)" })
        }
        lines.append(" */")
        return lines.joined(separator: "\n")
    }

    private func documentationLines(_ value: String) -> [String] {
        normalized(value)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { sanitizeLine(String($0)) }
    }

    private func normalized(_ value: String) -> String {
        let lines = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let first = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let last = lines.lastIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first, let last else { return "" }
        return lines[first...last].joined(separator: "\n")
    }

    private func sanitizeLine(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "*/", with: "*\\/")
        let indentation = result.prefix { $0 == " " || $0 == "\t" }
        let content = result.dropFirst(indentation.count)
        if content.hasPrefix("@") {
            result = String(indentation) + "&#64;" + content.dropFirst()
        }
        return result
    }
}
