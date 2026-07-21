internal import Foundation

internal enum TypeScriptIdentifier {
    internal static func isValid(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              first == "_" || first == "$" || CharacterSet.letters.contains(first) else {
            return false
        }
        let hasValidScalars = value.unicodeScalars.dropFirst().allSatisfy {
            $0 == "_" || $0 == "$" || CharacterSet.alphanumerics.contains($0)
        }
        return hasValidScalars && !reserved.contains(value)
    }

    internal static func isConservative(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        func isStart(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "_" || scalar == "$" ||
                (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
        let hasValidScalars = isStart(first) && value.unicodeScalars.dropFirst().allSatisfy {
            isStart($0) || (48...57).contains($0.value)
        }
        return hasValidScalars && !reserved.contains(value)
    }

    internal static func namespaceComponents(_ value: String) throws -> [String] {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty, components.allSatisfy(isValid) else {
            throw TypeScriptToolingError(
                "The TypeScript namespace '\(value)' must contain only valid identifier components."
            )
        }
        return components
    }

    private static let reserved: Set<String> = [
        "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "enum", "export",
        "extends", "false", "finally", "for", "function", "if", "import",
        "in", "instanceof", "let", "new", "null", "return", "static",
        "super", "switch", "this", "throw", "true", "try", "typeof",
        "var", "void", "while", "with", "yield", "implements", "interface",
        "package", "private", "protected", "public",
    ]
}
