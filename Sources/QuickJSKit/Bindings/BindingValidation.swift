internal enum BindingValidation {
    internal static func nameMessage(_ name: String, role: String) -> String? {
        name.isEmpty || name.contains("\0")
            ? "\(role) must be non-empty and contain no NUL characters."
            : nil
    }

    internal static func parameterNames(
        _ explicitNames: [String]?,
        arity: Int
    ) -> (names: [String], message: String?) {
        let names = explicitNames ?? (0..<arity).map { "argument\($0)" }
        guard names.count == arity else {
            return (
                names,
                "The number of parameter names must match the Swift closure arity."
            )
        }
        guard Set(names).count == names.count,
              names.allSatisfy(isConservativeIdentifier) else {
            return (
                names,
                "Parameter names must be unique valid JavaScript identifiers."
            )
        }
        return (names, nil)
    }

    internal static func hasDuplicateNames<S: Sequence>(_ names: S) -> Bool
    where S.Element == String {
        var seen: Set<String> = []
        for name in names where !seen.insert(name).inserted { return true }
        return false
    }

    private static func isConservativeIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        func isStart(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "_" || scalar == "$" ||
                (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
        let hasValidScalars = isStart(first) && name.unicodeScalars.dropFirst().allSatisfy {
            isStart($0) || (48...57).contains($0.value)
        }
        return hasValidScalars && !reservedParameterNames.contains(name)
    }

    private static let reservedParameterNames: Set<String> = [
        "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "enum", "export",
        "extends", "false", "finally", "for", "function", "if", "import",
        "in", "instanceof", "let", "new", "null", "return", "static",
        "super", "switch", "this", "throw", "true", "try", "typeof",
        "var", "void", "while", "with", "yield", "implements", "interface",
        "package", "private", "protected", "public",
    ]
}
