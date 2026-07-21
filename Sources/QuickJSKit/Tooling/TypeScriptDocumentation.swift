internal import Foundation

/// Structured TSDoc for a generated TypeScript declaration.
///
/// Documentation is detached metadata. It contains no runtime state and can be
/// retained in an environment snapshot after the originating runtime is gone.
public struct TypeScriptDocumentation: Sendable, Hashable, ExpressibleByStringLiteral {
    /// A concise description displayed prominently by TypeScript-aware IDEs.
    public let summary: String

    /// Additional behavioral, performance, or usage details.
    public let remarks: String?

    /// Complete usage examples rendered as TSDoc `@example` blocks.
    public let examples: [Example]

    /// Related symbols or resources rendered as TSDoc `@see` blocks.
    ///
    /// Values may contain TSDoc inline links such as `{@link User}`.
    public let seeAlso: [String]

    /// Migration guidance rendered as a TSDoc `@deprecated` block.
    public let deprecated: String?

    /// Creates declaration documentation.
    public init(
        summary: String,
        remarks: String? = nil,
        examples: [Example] = [],
        seeAlso: [String] = [],
        deprecated: String? = nil
    ) {
        self.summary = summary
        self.remarks = remarks
        self.examples = examples
        self.seeAlso = seeAlso
        self.deprecated = deprecated
    }

    /// Creates summary-only documentation from a string literal.
    public init(stringLiteral value: String) {
        self.init(summary: value)
    }

    /// A complete TypeScript usage example.
    public struct Example: Sendable, Hashable {
        /// An optional heading shown before the example body.
        public let title: String?

        /// Markdown content, commonly including a fenced TypeScript code block.
        public let body: String

        /// Creates a documented example.
        public init(title: String? = nil, body: String) {
            self.title = title
            self.body = body
        }
    }
}

/// Structured TSDoc for a generated TypeScript function or method.
public struct TypeScriptFunctionDocumentation:
    Sendable,
    Hashable,
    ExpressibleByStringLiteral
{
    /// A concise description displayed prominently by TypeScript-aware IDEs.
    public let summary: String

    /// Additional behavioral, performance, or usage details.
    public let remarks: String?

    /// Documentation keyed by the JavaScript parameter name.
    public let parameters: [String: String]

    /// Documentation for a non-`Void` result.
    public let returns: String?

    /// Errors that a throwing Swift binding can expose to JavaScript.
    public let errors: [ThrownError]

    /// Complete usage examples rendered as TSDoc `@example` blocks.
    public let examples: [TypeScriptDocumentation.Example]

    /// Related symbols or resources rendered as TSDoc `@see` blocks.
    public let seeAlso: [String]

    /// Migration guidance rendered as a TSDoc `@deprecated` block.
    public let deprecated: String?

    /// Creates function documentation.
    public init(
        summary: String,
        remarks: String? = nil,
        parameters: [String: String] = [:],
        returns: String? = nil,
        errors: [ThrownError] = [],
        examples: [TypeScriptDocumentation.Example] = [],
        seeAlso: [String] = [],
        deprecated: String? = nil
    ) {
        self.summary = summary
        self.remarks = remarks
        self.parameters = parameters
        self.returns = returns
        self.errors = errors
        self.examples = examples
        self.seeAlso = seeAlso
        self.deprecated = deprecated
    }

    /// Creates summary-only function documentation from a string literal.
    public init(stringLiteral value: String) {
        self.init(summary: value)
    }

    /// One documented error condition.
    public struct ThrownError: Sendable, Hashable {
        /// An optional TypeScript or JavaScript error symbol used in a link.
        public let reference: String?

        /// The condition under which the error is thrown or the promise rejects.
        public let description: String

        /// Creates an error condition.
        public init(reference: String? = nil, description: String) {
            self.reference = reference
            self.description = description
        }
    }
}

internal enum TypeScriptDocumentationValidation {
    internal static func message(
        for documentation: TypeScriptFunctionDocumentation?,
        parameterNames: [String]
    ) -> String? {
        guard let documentation else { return nil }
        if let message = invalidTextMessage(in: documentation.allText) { return message }
        if documentation.examples.contains(where: {
            $0.title?.contains("\n") == true || $0.title?.contains("\r") == true
        }) {
            return "Documented example titles must fit on one line."
        }
        let unknown = Set(documentation.parameters.keys).subtracting(parameterNames).sorted()
        if let name = unknown.first {
            return "Function documentation refers to unknown parameter '\(name)'."
        }
        if documentation.errors.contains(where: {
            $0.reference?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        }) {
            return "Documented error references must be non-empty when provided."
        }
        if documentation.errors.contains(where: {
            guard let reference = $0.reference else { return false }
            return reference.contains("\n") || reference.contains("\r")
                || reference.contains("{") || reference.contains("}")
                || reference.contains("*/")
        }) {
            return "Documented error references must be safe single-line TSDoc link targets."
        }
        if documentation.seeAlso.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Documented see-also references must be non-empty."
        }
        return nil
    }

    internal static func message(for documentation: TypeScriptDocumentation?) -> String? {
        guard let documentation else { return nil }
        if let message = invalidTextMessage(in: documentation.allText) { return message }
        if documentation.examples.contains(where: {
            $0.title?.contains("\n") == true || $0.title?.contains("\r") == true
        }) {
            return "Documented example titles must fit on one line."
        }
        if documentation.seeAlso.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Documented see-also references must be non-empty."
        }
        return nil
    }

    private static func invalidTextMessage(in values: [String]) -> String? {
        if values.contains(where: { $0.contains("\0") }) {
            return "TypeScript documentation must contain no NUL characters."
        }
        return nil
    }
}

private extension TypeScriptDocumentation {
    var allText: [String] {
        [summary] + [remarks, deprecated].compactMap { $0 } + seeAlso
            + examples.flatMap { [$0.title, $0.body].compactMap { $0 } }
    }
}

private extension TypeScriptFunctionDocumentation {
    var allText: [String] {
        [summary] + [remarks, returns, deprecated].compactMap { $0 }
            + parameters.flatMap { [$0.key, $0.value] }
            + errors.flatMap { [$0.reference, $0.description].compactMap { $0 } }
            + seeAlso
            + examples.flatMap { [$0.title, $0.body].compactMap { $0 } }
    }
}
