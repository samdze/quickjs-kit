internal import Foundation

/// Options controlling logical Swift paths in declaration source maps.
public struct TypeScriptSourceMapOptions: Sendable, Hashable {
    /// Rewrites one logical source prefix in generated maps.
    public struct PathMapping: Sendable, Hashable {
        /// The source prefix to match.
        public let sourcePrefix: String

        /// The replacement written to the source map.
        public let replacement: String

        /// Creates a path rewrite.
        public init(sourcePrefix: String, replacement: String) {
            self.sourcePrefix = sourcePrefix
            self.replacement = replacement
        }
    }

    /// An optional Source Map v3 `sourceRoot`.
    public var sourceRoot: String?

    /// Longest-prefix path rewrites applied to logical file identifiers.
    public var pathMappings: [PathMapping]

    /// Creates source-map options.
    public init(
        sourceRoot: String? = nil,
        pathMappings: [PathMapping] = []
    ) {
        self.sourceRoot = sourceRoot
        self.pathMappings = pathMappings
    }
}

/// A generated declaration file and its Source Map v3 artifact.
public struct TypeScriptDeclarationBundle: Sendable, Hashable {
    /// TypeScript declarations containing a `sourceMappingURL` directive.
    public let declarations: String

    /// The deterministic Source Map v3 JSON document.
    public let sourceMap: String

    /// Creates a declaration bundle.
    public init(declarations: String, sourceMap: String) {
        self.declarations = declarations
        self.sourceMap = sourceMap
    }
}

extension JavaScriptEnvironmentDescription {
    /// Generates TypeScript declarations and a logical Swift source map.
    public func typeScriptDeclarationBundle(
        options: TypeScriptDeclarationOptions = .init(),
        sourceMapOptions: TypeScriptSourceMapOptions = .init()
    ) throws -> TypeScriptDeclarationBundle {
        let declarations = try typeScriptDeclarations(options: options)
        let sourceMap = TypeScriptSourceMapRenderer(
            environment: self,
            declarations: declarations,
            options: sourceMapOptions
        ).render()
        return TypeScriptDeclarationBundle(
            declarations: declarations
                + "//# sourceMappingURL=quickjskit.generated.d.ts.map\n",
            sourceMap: sourceMap
        )
    }
}

private struct TypeScriptSourceMapRenderer {
    private struct Origin {
        let name: String
        let patterns: [String]
        let location: TypeScriptSourceLocation
    }

    let environment: JavaScriptEnvironmentDescription
    let declarations: String
    let options: TypeScriptSourceMapOptions

    func render() -> String {
        let lines = declarations.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        let origins = environmentOrigins() + schemaOrigins()
        var sources: [String] = []
        var sourceIndices: [String: Int] = [:]
        typealias Segment = (
                generatedColumn: Int,
                source: Int,
                sourceLine: Int,
                sourceColumn: Int,
                name: Int
        )
        var segmentsByLine: [Int: [Segment]] = [:]
        var names: [String] = []
        var nameIndices: [String: Int] = [:]
        var usedPositions: Set<String> = []

        for origin in origins {
            guard let generated = generatedPosition(
                for: origin.patterns,
                in: lines,
                excluding: usedPositions
            ) else { continue }
            usedPositions.insert("\(generated.line):\(generated.column)")
            let path = mappedPath(origin.location.fileID)
            let sourceIndex: Int
            if let existing = sourceIndices[path] {
                sourceIndex = existing
            } else {
                sourceIndex = sources.count
                sources.append(path)
                sourceIndices[path] = sourceIndex
            }
            let nameIndex: Int
            if let existing = nameIndices[origin.name] {
                nameIndex = existing
            } else {
                nameIndex = names.count
                names.append(origin.name)
                nameIndices[origin.name] = nameIndex
            }
            segmentsByLine[generated.line, default: []].append((
                generated.column,
                sourceIndex,
                max(0, origin.location.line - 1),
                max(0, origin.location.column - 1),
                nameIndex
            ))
        }

        var previousSource = 0
        var previousSourceLine = 0
        var previousSourceColumn = 0
        var previousName = 0
        let mappings = lines.indices.map { line -> String in
            guard let segments = segmentsByLine[line] else { return "" }
            var previousGeneratedColumn = 0
            return segments.sorted { $0.generatedColumn < $1.generatedColumn }.map {
                segment in
                let values = [
                    segment.generatedColumn - previousGeneratedColumn,
                    segment.source - previousSource,
                    segment.sourceLine - previousSourceLine,
                    segment.sourceColumn - previousSourceColumn,
                    segment.name - previousName,
                ]
                previousGeneratedColumn = segment.generatedColumn
                previousSource = segment.source
                previousSourceLine = segment.sourceLine
                previousSourceColumn = segment.sourceColumn
                previousName = segment.name
                return values.map(base64VLQ).joined()
            }.joined(separator: ",")
        }.joined(separator: ";")

        let sourceRoot = options.sourceRoot.map {
            "  \"sourceRoot\": \(quotedJSONString($0)),\n"
        } ?? ""
        let sourceList = sources.map(quotedJSONString).joined(separator: ", ")
        let nameList = names.map(quotedJSONString).joined(separator: ", ")
        return """
        {
          "version": 3,
          "file": "quickjskit.generated.d.ts",
        \(sourceRoot)  "sources": [\(sourceList)],
          "names": [\(nameList)],
          "mappings": \(quotedJSONString(mappings))
        }
        """ + "\n"
    }

    private func generatedPosition(
        for patterns: [String],
        in lines: [String],
        excluding usedPositions: Set<String>
    ) -> (line: Int, column: Int)? {
        for lineIndex in lines.indices {
            for pattern in patterns {
                var searchStart = lines[lineIndex].startIndex
                while let range = lines[lineIndex].range(
                    of: pattern,
                    range: searchStart..<lines[lineIndex].endIndex
                ) {
                    let column = lines[lineIndex][..<range.lowerBound].utf16.count
                    if !usedPositions.contains("\(lineIndex):\(column)") {
                        return (lineIndex, column)
                    }
                    searchStart = range.upperBound
                }
            }
        }
        return nil
    }

    private func mappedPath(_ path: String) -> String {
        if let mapping = options.pathMappings
            .filter({ path.hasPrefix($0.sourcePrefix) })
            .max(by: { $0.sourcePrefix.count < $1.sourcePrefix.count }) {
            return mapping.replacement + path.dropFirst(mapping.sourcePrefix.count)
        }
        guard path.hasPrefix("/") else { return path }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func schemaOrigins() -> [Origin] {
        var schemas = environment.additionalSchemas
        for global in environment.globals {
            collectSchemas(from: global, into: &schemas)
        }
        for module in environment.modules {
            if case let .swift(_, _, members) = module {
                for member in members { collectSchemas(from: member, into: &schemas) }
            }
        }
        return schemas.flatMap { schema in
            schema.definitions.flatMap { definition -> [Origin] in
                guard let location = definition.sourceLocation ?? schema.sourceLocation else {
                    return []
                }
                var result = [Origin(
                    name: definition.name,
                    patterns: [
                        "interface \(definition.name)",
                        "type \(definition.name)",
                    ],
                    location: location
                )]
                switch definition.kind {
                case let .interface(properties):
                    for property in properties {
                        guard let propertyLocation = property.sourceLocation else { continue }
                        let key = sourceMapPropertyKey(property.name)
                        result.append(
                            Origin(
                                name: "\(definition.name).\(property.name)",
                                patterns: ["\(key)?: ", "\(key): "],
                                location: propertyLocation
                            )
                        )
                    }
                case let .enumeration(cases):
                    for enumCase in cases {
                        guard let caseLocation = enumCase.sourceLocation else { continue }
                        result.append(
                            Origin(
                                name: "\(definition.name).\(enumCase.name)",
                                patterns: [renderTypeScriptLiteral(enumCase.value)],
                                location: caseLocation
                            )
                        )
                    }
                case .alias:
                    break
                }
                return result
            }
        }.sorted {
            if $0.location.fileID != $1.location.fileID {
                return $0.location.fileID < $1.location.fileID
            }
            if $0.location.line != $1.location.line {
                return $0.location.line < $1.location.line
            }
            return $0.name < $1.name
        }
    }

    private func sourceMapPropertyKey(_ name: String) -> String {
        TypeScriptIdentifier.isValid(name) ? name : quotedJSONString(name)
    }

    private func environmentOrigins() -> [Origin] {
        var result: [Origin] = []
        for global in environment.globals {
            switch global {
            case let .function(function):
                append(function, patterns: ["function \(function.name)("], to: &result)
            case let .object(objectName, _, members):
                for member in members {
                    switch member {
                    case let .function(function):
                        append(function, patterns: ["\(function.name)("], to: &result)
                    case let .value(value):
                        append(
                            value,
                            name: "\(objectName).\(value.name)",
                            patterns: ["\(sourceMapPropertyKey(value.name)): "],
                            to: &result
                        )
                    }
                }
            case let .value(value):
                append(
                    value,
                    name: value.name,
                    patterns: ["declare let \(value.name): "],
                    to: &result
                )
            }
        }
        for module in environment.modules {
            guard case let .swift(_, _, members) = module else { continue }
            for member in members {
                switch member {
                case let .function(function):
                    append(
                        function,
                        patterns: ["function \(function.name)("],
                        to: &result
                    )
                case let .value(value):
                    append(
                        value,
                        name: value.name,
                        patterns: ["const \(value.name): "],
                        to: &result
                    )
                }
            }
        }
        return result
    }

    private func append(
        _ value: EnvironmentValueDescription,
        name: String,
        patterns: [String],
        to result: inout [Origin]
    ) {
        guard let location = value.sourceLocation else { return }
        result.append(Origin(name: name, patterns: patterns, location: location))
    }

    private func append(
        _ function: EnvironmentFunctionDescription,
        patterns: [String],
        to result: inout [Origin]
    ) {
        guard let location = function.sourceLocation else { return }
        result.append(
            Origin(name: function.name, patterns: patterns, location: location)
        )
        for parameter in function.parameters {
            guard let parameterLocation = parameter.sourceLocation else { continue }
            result.append(
                Origin(
                    name: "\(function.name).\(parameter.name)",
                    patterns: ["\(parameter.name)?: ", "\(parameter.name): "],
                    location: parameterLocation
                )
            )
        }
    }

    private func collectSchemas(
        from global: EnvironmentGlobalDescription,
        into schemas: inout [TypeScriptSchema]
    ) {
        switch global {
        case let .function(function): collectSchemas(from: function, into: &schemas)
        case let .object(_, _, members):
            for member in members { collectSchemas(from: member, into: &schemas) }
        case let .value(value): collectSchemas(from: value.type, into: &schemas)
        }
    }

    private func collectSchemas(
        from member: EnvironmentMemberDescription,
        into schemas: inout [TypeScriptSchema]
    ) {
        switch member {
        case let .function(function): collectSchemas(from: function, into: &schemas)
        case let .value(value): collectSchemas(from: value.type, into: &schemas)
        }
    }

    private func collectSchemas(
        from function: EnvironmentFunctionDescription,
        into schemas: inout [TypeScriptSchema]
    ) {
        for parameter in function.parameters {
            collectSchemas(from: parameter.type, into: &schemas)
        }
        collectSchemas(from: function.result, into: &schemas)
    }

    private func collectSchemas(
        from shape: BindingTypeShape,
        into schemas: inout [TypeScriptSchema]
    ) {
        switch shape {
        case let .optional(wrapped), let .array(wrapped), let .dictionary(wrapped):
            collectSchemas(from: wrapped, into: &schemas)
        case let .codable(_, schema?): schemas.append(schema)
        default: break
        }
    }

    private func base64VLQ(_ value: Int) -> String {
        let alphabet = Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        )
        var encoded = value < 0 ? ((-value) << 1) | 1 : value << 1
        var result = ""
        repeat {
            var digit = encoded & 31
            encoded >>= 5
            if encoded > 0 { digit |= 32 }
            result.append(alphabet[digit])
        } while encoded > 0
        return result
    }
}
