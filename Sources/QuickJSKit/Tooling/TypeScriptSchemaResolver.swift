internal enum ResolvedTypeScriptScope: Sendable, Hashable, Comparable {
    case global
    case namespace([String])
    case module(String)

    internal static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.global, .global): false
        case (.global, _): true
        case (_, .global): false
        case let (.namespace(lhs), .namespace(rhs)): lhs.lexicographicallyPrecedes(rhs)
        case (.namespace, .module): true
        case (.module, .namespace): false
        case let (.module(lhs), .module(rhs)): lhs < rhs
        }
    }

    internal var displayName: String {
        switch self {
        case .global: "global scope"
        case let .namespace(components): "namespace '\(components.joined(separator: "."))'"
        case let .module(specifier): "module '\(specifier)'"
        }
    }

    internal func qualifiedName(_ name: String) -> String {
        switch self {
        case .global: name
        case let .namespace(components): (components + [name]).joined(separator: ".")
        case let .module(specifier): "module '\(specifier)'.\(name)"
        }
    }
}

internal struct ResolvedTypeScriptDefinitionKey: Sendable, Hashable {
    internal let scope: ResolvedTypeScriptScope
    internal let name: String
}

internal struct ResolvedTypeScriptSchemaKey: Sendable, Hashable {
    internal let schema: TypeScriptSchema
    internal let scope: ResolvedTypeScriptScope
}

internal indirect enum ResolvedTypeScriptType: Sendable, Hashable {
    case boolean
    case string
    case number
    case bigint
    case null
    case undefined
    case unknown
    case date
    case uint8Array
    case named(ResolvedTypeScriptDefinitionKey)
    case array(ResolvedTypeScriptType)
    case record(ResolvedTypeScriptType)
    case union([ResolvedTypeScriptType])
    case literal(TypeScriptLiteral)
}

internal struct ResolvedTypeScriptProperty: Sendable, Hashable {
    internal let name: String
    internal let type: ResolvedTypeScriptType
    internal let isOptional: Bool
    internal let isReadonly: Bool
    internal let documentation: TypeScriptDocumentation?
    internal let defaultValue: String?
}

internal struct ResolvedTypeScriptDefinition: Sendable, Hashable {
    internal enum Kind: Sendable, Hashable {
        case interface(properties: [ResolvedTypeScriptProperty])
        case alias(ResolvedTypeScriptType)
        case enumeration(cases: [TypeScriptEnumCase])
    }

    internal let key: ResolvedTypeScriptDefinitionKey
    internal let documentation: TypeScriptDocumentation?
    internal let kind: Kind
}

internal struct ResolvedTypeScriptEnvironment {
    internal let definitions: [ResolvedTypeScriptDefinition]
    internal let schemaTypes: [ResolvedTypeScriptSchemaKey: ResolvedTypeScriptType]

    internal func definitions(in scope: ResolvedTypeScriptScope) -> [ResolvedTypeScriptDefinition] {
        definitions.filter { $0.key.scope == scope }
    }

    internal func schemaType(
        _ schema: TypeScriptSchema,
        from scope: ResolvedTypeScriptScope
    ) -> ResolvedTypeScriptType? {
        if let type = schemaTypes[.init(schema: schema, scope: scope)] {
            return type
        }
        let matches = schemaTypes.filter { $0.key.schema == schema }
        return matches.count == 1 ? matches.first?.value : nil
    }
}

internal struct TypeScriptSchemaResolver {
    internal let environment: JavaScriptEnvironmentDescription
    internal let options: TypeScriptDeclarationOptions

    private struct CollectedSchema {
        let schema: TypeScriptSchema
        let origin: ResolvedTypeScriptScope?
    }

    private struct SchemaOwnershipKey: Hashable {
        let schema: TypeScriptSchema

        init(_ schema: TypeScriptSchema) {
            self.schema = TypeScriptSchema(
                type: schema.type,
                definitions: schema.definitions,
                scope: nil,
                sourceLocation: schema.sourceLocation
            )
        }
    }

    private struct DefinitionOwnershipKey: Hashable {
        let definition: TypeScriptDefinition

        init(_ definition: TypeScriptDefinition) {
            self.definition = TypeScriptDefinition(
                name: definition.name,
                scope: nil,
                documentation: definition.documentation,
                sourceLocation: definition.sourceLocation,
                kind: definition.kind
            )
        }
    }

    internal func resolve() throws -> ResolvedTypeScriptEnvironment {
        let knownModules = Set(environment.modules.map(\.specifier))
        let defaultScope = try resolve(options.defaultTypeScope, knownModules: knownModules)
        let schemas = collectedSchemas()

        var schemaOwners: [SchemaOwnershipKey: Set<ResolvedTypeScriptScope>] = [:]
        var definitionOwners: [DefinitionOwnershipKey: Set<ResolvedTypeScriptScope>] = [:]
        try collectOwners(
            into: &schemaOwners,
            definitions: &definitionOwners,
            knownModules: knownModules
        )

        var schemaScopes: [ResolvedTypeScriptSchemaKey: ResolvedTypeScriptScope] = [:]
        var candidates: [(TypeScriptDefinition, ResolvedTypeScriptScope)] = []
        var availableKeys: Set<ResolvedTypeScriptDefinitionKey> = []

        for collected in schemas {
            let schema = collected.schema
            let schemaScope = try schema.scope.map {
                try resolve($0, knownModules: knownModules)
            } ?? uniqueOwner(
                schemaOwners[SchemaOwnershipKey(schema)],
                for: "schema '\(schema.primaryName)'"
            ) ?? collected.origin ?? defaultScope
            let schemaKey = ResolvedTypeScriptSchemaKey(
                schema: schema,
                scope: schemaScope
            )
            schemaScopes[schemaKey] = schemaScope
            for definition in schema.definitions {
                guard TypeScriptIdentifier.isValid(definition.name) else {
                    throw TypeScriptToolingError(
                        "The TypeScript definition name '\(definition.name)' is not a valid identifier."
                    )
                }
                try validateStructure(definition)
                let scope = try definition.scope.map {
                    try resolve($0, knownModules: knownModules)
                } ?? uniqueOwner(
                    definitionOwners[DefinitionOwnershipKey(definition)],
                    for: "definition '\(definition.name)'"
                ) ?? schemaScope
                candidates.append((definition, scope))
                availableKeys.insert(.init(scope: scope, name: definition.name))
            }
        }

        var definitions: [ResolvedTypeScriptDefinitionKey: ResolvedTypeScriptDefinition] = [:]
        for (definition, scope) in candidates {
            let resolved = try resolve(
                definition,
                in: scope,
                availableKeys: availableKeys,
                knownModules: knownModules
            )
            if let existing = definitions[resolved.key], existing != resolved {
                throw TypeScriptToolingError(
                    "Conflicting TypeScript definitions use '\(resolved.key.scope.qualifiedName(resolved.key.name))'."
                )
            }
            definitions[resolved.key] = resolved
        }

        var schemaTypes: [ResolvedTypeScriptSchemaKey: ResolvedTypeScriptType] = [:]
        for schemaKey in schemaScopes.keys {
            let schema = schemaKey.schema
            let scope = schemaKey.scope
            schemaTypes[schemaKey] = try resolve(
                schema.type,
                in: scope,
                availableKeys: availableKeys,
                knownModules: knownModules
            )
        }

        return ResolvedTypeScriptEnvironment(
            definitions: definitions.values.sorted {
                $0.key.scope == $1.key.scope
                    ? $0.key.name < $1.key.name
                    : $0.key.scope < $1.key.scope
            },
            schemaTypes: schemaTypes
        )
    }

    private func resolve(
        _ scope: TypeScriptDeclarationScope,
        knownModules: Set<String>
    ) throws -> ResolvedTypeScriptScope {
        switch scope {
        case .global:
            return .global
        case let .namespace(name):
            return .namespace(try TypeScriptIdentifier.namespaceComponents(name))
        case let .module(specifier):
            guard knownModules.contains(specifier) else {
                throw TypeScriptToolingError(
                    "TypeScript declaration scope references unknown module '\(specifier)'."
                )
            }
            return .module(specifier)
        }
    }

    private func resolve(
        _ definition: TypeScriptDefinition,
        in scope: ResolvedTypeScriptScope,
        availableKeys: Set<ResolvedTypeScriptDefinitionKey>,
        knownModules: Set<String>
    ) throws -> ResolvedTypeScriptDefinition {
        let kind: ResolvedTypeScriptDefinition.Kind
        switch definition.kind {
        case let .interface(properties):
            kind = .interface(
                properties: try properties.map {
                    ResolvedTypeScriptProperty(
                        name: $0.name,
                        type: try resolve(
                            $0.type,
                            in: scope,
                            availableKeys: availableKeys,
                            knownModules: knownModules
                        ),
                        isOptional: $0.isOptional,
                        isReadonly: $0.isReadonly,
                        documentation: $0.documentation,
                        defaultValue: $0.defaultValue
                    )
                }
            )
        case let .alias(type):
            kind = .alias(
                try resolve(
                    type,
                    in: scope,
                    availableKeys: availableKeys,
                    knownModules: knownModules
                )
            )
        case let .enumeration(cases):
            kind = .enumeration(cases: cases)
        }
        return ResolvedTypeScriptDefinition(
            key: .init(scope: scope, name: definition.name),
            documentation: definition.documentation,
            kind: kind
        )
    }

    private func resolve(
        _ type: TypeScriptType,
        in lexicalScope: ResolvedTypeScriptScope,
        availableKeys: Set<ResolvedTypeScriptDefinitionKey>,
        knownModules: Set<String>
    ) throws -> ResolvedTypeScriptType {
        switch type {
        case .boolean: return .boolean
        case .string: return .string
        case .number: return .number
        case .bigint: return .bigint
        case .null: return .null
        case .undefined: return .undefined
        case .unknown: return .unknown
        case .date: return .date
        case .uint8Array: return .uint8Array
        case let .named(name, declaredScope):
            guard TypeScriptIdentifier.isValid(name) else {
                throw TypeScriptToolingError("The TypeScript reference '\(name)' is not valid.")
            }
            let targetScope: ResolvedTypeScriptScope
            if let declaredScope {
                targetScope = try resolve(declaredScope, knownModules: knownModules)
            } else {
                let local = ResolvedTypeScriptDefinitionKey(
                    scope: lexicalScope,
                    name: name
                )
                if availableKeys.contains(local) {
                    targetScope = lexicalScope
                } else {
                    let matches = availableKeys.filter { $0.name == name }
                    guard matches.count == 1, let match = matches.first else {
                        if matches.isEmpty {
                            throw TypeScriptToolingError(
                                "TypeScript schema reference '\(lexicalScope.qualifiedName(name))' has no matching definition."
                            )
                        }
                        let destinations = matches
                            .map { $0.scope.qualifiedName($0.name) }
                            .sorted()
                            .joined(separator: ", ")
                        throw TypeScriptToolingError(
                            "TypeScript schema reference '\(name)' is ambiguous; matching definitions are \(destinations)."
                        )
                    }
                    targetScope = match.scope
                }
            }
            let key = ResolvedTypeScriptDefinitionKey(scope: targetScope, name: name)
            guard availableKeys.contains(key) else {
                throw TypeScriptToolingError(
                    "TypeScript schema reference '\(targetScope.qualifiedName(name))' has no matching definition."
                )
            }
            if declaredScope == .global {
                try validateGlobalReference(name, from: lexicalScope, availableKeys: availableKeys)
            }
            return .named(key)
        case let .array(element):
            return .array(
                try resolve(
                    element,
                    in: lexicalScope,
                    availableKeys: availableKeys,
                    knownModules: knownModules
                )
            )
        case let .record(value):
            return .record(
                try resolve(
                    value,
                    in: lexicalScope,
                    availableKeys: availableKeys,
                    knownModules: knownModules
                )
            )
        case let .union(types):
            guard !types.isEmpty else {
                throw TypeScriptToolingError("A TypeScript union must contain at least one type.")
            }
            return .union(
                try types.map {
                    try resolve(
                        $0,
                        in: lexicalScope,
                        availableKeys: availableKeys,
                        knownModules: knownModules
                    )
                }
            )
        case let .literal(literal):
            return .literal(literal)
        }
    }

    private func validateGlobalReference(
        _ name: String,
        from lexicalScope: ResolvedTypeScriptScope,
        availableKeys: Set<ResolvedTypeScriptDefinitionKey>
    ) throws {
        let shadows: Bool
        switch lexicalScope {
        case .global:
            shadows = false
        case let .module(specifier):
            shadows = availableKeys.contains(
                .init(scope: .module(specifier), name: name)
            )
        case let .namespace(components):
            shadows = (1...components.count).reversed().contains { count in
                availableKeys.contains(
                    .init(scope: .namespace(Array(components.prefix(count))), name: name)
                )
            }
        }
        if shadows {
            throw TypeScriptToolingError(
                "Global TypeScript reference '\(name)' is shadowed in \(lexicalScope.displayName)."
            )
        }
    }

    private func validateStructure(_ definition: TypeScriptDefinition) throws {
        switch definition.kind {
        case let .interface(properties):
            var names: Set<String> = []
            for property in properties {
                guard names.insert(property.name).inserted else {
                    throw TypeScriptToolingError(
                        "The TypeScript interface '\(definition.name)' contains duplicate property '\(property.name)'."
                    )
                }
                if property.defaultValue?.contains("\0") == true {
                    throw TypeScriptToolingError(
                        "The default value for TypeScript property "
                            + "'\(definition.name).\(property.name)' must contain no NUL characters."
                    )
                }
            }
        case .alias:
            break
        case let .enumeration(cases):
            guard !cases.isEmpty else {
                throw TypeScriptToolingError(
                    "The TypeScript literal union '\(definition.name)' must contain at least one case."
                )
            }
            guard Set(cases.map(\.value)).count == cases.count else {
                throw TypeScriptToolingError(
                    "The TypeScript literal union '\(definition.name)' contains duplicate values."
                )
            }
        }
    }

    private func collectedSchemas() -> [CollectedSchema] {
        var schemas = environment.additionalSchemas.map {
            CollectedSchema(schema: $0, origin: nil)
        }
        for global in environment.globals {
            collectSchemas(from: global, origin: .global, into: &schemas)
        }
        for module in environment.modules {
            guard case let .swift(specifier, _, _) = module else { continue }
            collectSchemas(
                from: module,
                origin: .module(specifier),
                into: &schemas
            )
        }
        return schemas
    }

    private func collectSchemas(
        from global: EnvironmentGlobalDescription,
        origin: ResolvedTypeScriptScope,
        into schemas: inout [CollectedSchema]
    ) {
        switch global {
        case let .function(function):
            collectSchemas(from: function, origin: origin, into: &schemas)
        case let .object(_, _, members):
            for member in members {
                collectSchemas(from: member, origin: origin, into: &schemas)
            }
        case let .type(type):
            if let schema = type.schema {
                schemas.append(CollectedSchema(schema: schema, origin: origin))
            }
        case let .value(value):
            collectSchemas(from: value.type, origin: origin, into: &schemas)
        }
    }

    private func collectSchemas(
        from module: EnvironmentModuleDescription,
        origin: ResolvedTypeScriptScope,
        into schemas: inout [CollectedSchema]
    ) {
        guard case let .swift(_, _, members) = module else { return }
        for member in members {
            collectSchemas(from: member, origin: origin, into: &schemas)
        }
    }

    private func collectSchemas(
        from member: EnvironmentMemberDescription,
        origin: ResolvedTypeScriptScope,
        into schemas: inout [CollectedSchema]
    ) {
        switch member {
        case let .function(function):
            collectSchemas(from: function, origin: origin, into: &schemas)
        case let .type(type):
            if let schema = type.schema {
                schemas.append(CollectedSchema(schema: schema, origin: origin))
            }
        case let .value(value):
            collectSchemas(from: value.type, origin: origin, into: &schemas)
        }
    }

    private func collectSchemas(
        from function: EnvironmentFunctionDescription,
        origin: ResolvedTypeScriptScope,
        into schemas: inout [CollectedSchema]
    ) {
        for parameter in function.parameters {
            collectSchemas(from: parameter.type, origin: origin, into: &schemas)
        }
        collectSchemas(from: function.result, origin: origin, into: &schemas)
    }

    private func collectSchemas(
        from shape: BindingTypeShape,
        origin: ResolvedTypeScriptScope,
        into schemas: inout [CollectedSchema]
    ) {
        switch shape {
        case let .optional(wrapped), let .array(wrapped), let .dictionary(wrapped):
            collectSchemas(from: wrapped, origin: origin, into: &schemas)
        case let .codable(_, schema?):
            schemas.append(CollectedSchema(schema: schema, origin: origin))
        default:
            break
        }
    }

    private func collectOwners(
        into schemaOwners: inout [SchemaOwnershipKey: Set<ResolvedTypeScriptScope>],
        definitions definitionOwners: inout [DefinitionOwnershipKey: Set<ResolvedTypeScriptScope>],
        knownModules: Set<String>
    ) throws {
        func add(
            _ schema: TypeScriptSchema,
            primaryName: String,
            at scope: ResolvedTypeScriptScope
        ) {
            schemaOwners[SchemaOwnershipKey(schema), default: []].insert(scope)
            for definition in schema.definitions {
                guard definition.name == primaryName else { continue }
                definitionOwners[DefinitionOwnershipKey(definition), default: []].insert(scope)
            }
        }

        for global in environment.globals {
            guard case let .type(type) = global, let schema = type.schema else { continue }
            add(
                schema,
                primaryName: type.name,
                at: try schema.scope.map { try resolve($0, knownModules: knownModules) }
                    ?? .global
            )
        }
        for module in environment.modules {
            guard case let .swift(specifier, _, members) = module else { continue }
            let scope = ResolvedTypeScriptScope.module(specifier)
            for member in members {
                guard case let .type(type) = member, let schema = type.schema else { continue }
                add(
                    schema,
                    primaryName: type.name,
                    at: try schema.scope.map { try resolve($0, knownModules: knownModules) }
                        ?? scope
                )
            }
        }
    }

    private func uniqueOwner(
        _ owners: Set<ResolvedTypeScriptScope>?,
        for description: String
    ) throws -> ResolvedTypeScriptScope? {
        guard let owners, !owners.isEmpty else { return nil }
        guard owners.count == 1, let owner = owners.first else {
            let scopes = owners.map(\.displayName).sorted().joined(separator: ", ")
            throw TypeScriptToolingError(
                "The \(description) has multiple declaration locations: \(scopes)."
            )
        }
        return owner
    }
}

private extension TypeScriptSchema {
    var primaryName: String {
        switch type {
        case let .named(name, _): return name
        default: return "<anonymous>"
        }
    }
}
