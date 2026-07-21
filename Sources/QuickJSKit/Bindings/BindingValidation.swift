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
              names.allSatisfy(TypeScriptIdentifier.isConservative) else {
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

}
