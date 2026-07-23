import SwiftSyntax
import SwiftSyntaxMacros

struct ParsedExport {
    let swiftName: String
    let javaScriptName: String
    let scopeExpression: String
    let documentationExpression: String
    let sourceLocationExpression: String
    let kind: Kind

    enum Kind {
        case structure([ModelProperty])
        case enumeration([EnumCase])
        case host(Host)
    }

    struct ModelProperty {
        let name: String
        let typeExpression: String
        let isOptional: Bool
        let documentationExpression: String
        let defaultValueExpression: String
        let sourceLocationExpression: String
        let dependencies: Set<String>
    }

    struct EnumCase {
        let name: String
        let literalExpression: String
        let documentationExpression: String
        let sourceLocationExpression: String
    }

    struct Host {
        let constructors: [String]
        let instanceMembers: [String]
        let staticMembers: [String]
    }
}

enum ExportSyntaxAnalyzer {
    static func analyze(
        attribute: AttributeSyntax,
        declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) throws -> ParsedExport {
        let swiftName = try declarationName(declaration)
        let javaScriptName = renamedJavaScriptName(in: declaration.attributes) ?? swiftName
        try validateName(javaScriptName, at: declaration)

        let common = (
            swiftName: swiftName,
            javaScriptName: javaScriptName,
            scope: scopeExpression(attribute),
            documentation: documentation(of: declaration).declarationExpression,
            location: sourceLocationExpression(of: declaration, in: context)
        )

        if let structure = declaration.as(StructDeclSyntax.self) {
            try rejectCustomCodable(in: structure)
            try rejectLiveMembers(in: structure)
            let properties = try modelProperties(structure, context: context)
            return ParsedExport(
                swiftName: common.swiftName,
                javaScriptName: common.javaScriptName,
                scopeExpression: common.scope,
                documentationExpression: common.documentation,
                sourceLocationExpression: common.location,
                kind: .structure(properties)
            )
        }
        if let enumeration = declaration.as(EnumDeclSyntax.self) {
            try rejectCustomCodable(in: enumeration)
            try rejectLiveMembers(in: enumeration)
            let cases = try enumCases(enumeration, context: context)
            return ParsedExport(
                swiftName: common.swiftName,
                javaScriptName: common.javaScriptName,
                scopeExpression: common.scope,
                documentationExpression: common.documentation,
                sourceLocationExpression: common.location,
                kind: .enumeration(cases)
            )
        }
        if let classDeclaration = declaration.as(ClassDeclSyntax.self) {
            guard classDeclaration.modifiers.contains(where: {
                $0.name.tokenKind == .keyword(.final)
            }) else {
                throw macroFailure(.classMustBeFinal, at: classDeclaration.name)
            }
            let host = try host(
                declaration,
                rootType: swiftName,
                isActor: false,
                context: context
            )
            return ParsedExport(
                swiftName: common.swiftName,
                javaScriptName: common.javaScriptName,
                scopeExpression: common.scope,
                documentationExpression: common.documentation,
                sourceLocationExpression: common.location,
                kind: .host(host)
            )
        }
        if declaration.is(ActorDeclSyntax.self) {
            let host = try host(
                declaration,
                rootType: swiftName,
                isActor: true,
                context: context
            )
            return ParsedExport(
                swiftName: common.swiftName,
                javaScriptName: common.javaScriptName,
                scopeExpression: common.scope,
                documentationExpression: common.documentation,
                sourceLocationExpression: common.location,
                kind: .host(host)
            )
        }
        throw macroFailure(.unsupportedDeclaration, at: declaration)
    }

    private static func scopeExpression(_ attribute: AttributeSyntax) -> String {
        guard case let .argumentList(arguments) = attribute.arguments,
              let argument = arguments.first else {
            return "nil"
        }
        return argument.expression.trimmedDescription
    }

    // MARK: Value types

    private static func rejectCustomCodable(
        in declaration: some DeclGroupSyntax
    ) throws {
        for member in declaration.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self),
               function.name.text == "encode",
               let parameter = function.signature.parameterClause.parameters.first,
               parameter.firstName.text == "to",
               parameter.type.trimmedDescription == "Encoder"
                    || parameter.type.trimmedDescription == "any Encoder" {
                throw macroFailure(.customCodable("encode(to:)"), at: function.name)
            }
            if let initializer = member.decl.as(InitializerDeclSyntax.self),
               let parameter = initializer.signature.parameterClause.parameters.first,
               parameter.firstName.text == "from",
               parameter.type.trimmedDescription == "Decoder"
                    || parameter.type.trimmedDescription == "any Decoder" {
                throw macroFailure(.customCodable("init(from:)"), at: initializer.initKeyword)
            }
        }
    }

    private static func rejectLiveMembers(
        in declaration: some DeclGroupSyntax
    ) throws {
        for member in declaration.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self),
               !hasAttribute("JavaScriptIgnore", on: function.attributes) {
                throw macroFailure(.valueMemberRequiresIgnore, at: function.name)
            }
        }
    }

    private static func modelProperties(
        _ declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) throws -> [ParsedExport.ModelProperty] {
        let codingKeys = try codingKeyNames(in: declaration)
        var storedNames: Set<String> = []
        var result: [ParsedExport.ModelProperty] = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  !isTypeProperty(variable.modifiers) else {
                continue
            }
            let wrapper = firstPropertyWrapper(in: variable.attributes)
            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                let name = pattern.identifier.text
                guard isStoredProperty(binding) else { continue }
                storedNames.insert(name)
                if let wrapper {
                    throw macroFailure(.propertyWrapper(name), at: wrapper)
                }
                if variable.modifiers.contains(where: {
                    $0.name.tokenKind == .keyword(.lazy)
                }) {
                    throw macroFailure(.lazyProperty(name), at: variable)
                }
                guard let annotation = binding.typeAnnotation else {
                    throw macroFailure(
                        .propertyRequiresExplicitType(name),
                        at: binding.pattern
                    )
                }
                if let codingKeys, codingKeys[name] == nil { continue }
                let encodedName = codingKeys?[name] ?? name
                let resolved = try resolveTypeScriptType(annotation.type)
                let parsedDocumentation = documentation(of: variable)
                result.append(
                    .init(
                        name: encodedName,
                        typeExpression: resolved.expression,
                        isOptional: resolved.isOptional,
                        documentationExpression:
                            parsedDocumentation.declarationExpression,
                        defaultValueExpression:
                            parsedDocumentation.defaultValue.map(swiftLiteral) ?? "nil",
                        sourceLocationExpression:
                            sourceLocationExpression(of: binding, in: context),
                        dependencies: resolved.dependencies
                    )
                )
            }
        }
        if let codingKeys,
           let unknown = codingKeys.names.keys
            .filter({ !storedNames.contains($0) })
            .sorted()
            .first,
           let node = codingKeys.nodes[unknown] {
            throw macroFailure(
                .malformedCodingKeys(
                    "case '\(unknown)' does not match a stored instance property."
                ),
                at: node
            )
        }
        return result
    }

    private struct ParsedCodingKeys {
        let names: [String: String]
        let nodes: [String: Syntax]

        subscript(_ name: String) -> String? {
            names[name]
        }
    }

    private static func codingKeyNames(
        in declaration: some DeclGroupSyntax
    ) throws -> ParsedCodingKeys? {
        let declarations = declaration.memberBlock.members.compactMap {
            $0.decl.as(EnumDeclSyntax.self)
        }.filter { $0.name.text == "CodingKeys" }
        guard declarations.count <= 1 else {
            throw macroFailure(
                .malformedCodingKeys("declare CodingKeys only once."),
                at: declarations[1].name
            )
        }
        guard let codingKeys = declarations.first else { return nil }
        let inheritedTypes = codingKeys.inheritanceClause?.inheritedTypes.compactMap {
            unqualifiedInheritedTypeName($0.type)
        } ?? []
        guard Set(inheritedTypes) == ["String", "CodingKey"],
              inheritedTypes.count == 2 else {
            let node = codingKeys.inheritanceClause.map(Syntax.init)
                ?? Syntax(codingKeys.name)
            throw macroFailure(
                .malformedCodingKeys(
                    "declare it as 'enum CodingKeys: String, CodingKey'."
                ),
                at: node
            )
        }
        var result: [String: String] = [:]
        var nodes: [String: Syntax] = [:]
        var encodedNames: Set<String> = []
        for member in codingKeys.memberBlock.members {
            guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else {
                throw macroFailure(
                    .malformedCodingKeys("only enum cases are supported."),
                    at: member.decl
                )
            }
            for element in cases.elements {
                guard element.parameterClause == nil else {
                    throw macroFailure(
                        .malformedCodingKeys("cases cannot have associated values."),
                        at: element
                    )
                }
                let swiftName = element.name.text
                let encodedName: String
                if let rawValue = element.rawValue {
                    guard let literal = rawValue.value.as(StringLiteralExprSyntax.self),
                          literal.segments.count == 1,
                          case let .stringSegment(segment) = literal.segments.first else {
                        throw macroFailure(
                            .malformedCodingKeys("raw values must be static string literals."),
                            at: rawValue.value
                        )
                    }
                    encodedName = segment.content.text
                } else {
                    encodedName = swiftName
                }
                guard result.updateValue(encodedName, forKey: swiftName) == nil else {
                    throw macroFailure(
                        .malformedCodingKeys("case '\(swiftName)' is duplicated."),
                        at: element.name
                    )
                }
                nodes[swiftName] = Syntax(element.name)
                guard encodedNames.insert(encodedName).inserted else {
                    throw macroFailure(
                        .malformedCodingKeys("encoded name '\(encodedName)' is duplicated."),
                        at: element.name
                    )
                }
            }
        }
        return .init(names: result, nodes: nodes)
    }

    private static func enumCases(
        _ declaration: EnumDeclSyntax,
        context: some MacroExpansionContext
    ) throws -> [ParsedExport.EnumCase] {
        let inherited = declaration.inheritanceClause?.inheritedTypes.compactMap {
            unqualifiedInheritedTypeName($0.type)
        } ?? []
        let rawTypes = inherited.filter { $0 == "String" || $0 == "Int" }
        guard rawTypes.count == 1 else {
            let node = declaration.inheritanceClause.map(Syntax.init)
                ?? Syntax(declaration.name)
            throw macroFailure(
                .unsupportedEnumRepresentation,
                at: node
            )
        }
        let isString = rawTypes[0] == "String"
        var nextInteger: Int64? = 0
        var result: [ParsedExport.EnumCase] = []
        for member in declaration.memberBlock.members {
            guard let caseDeclaration = member.decl.as(EnumCaseDeclSyntax.self) else {
                continue
            }
            for element in caseDeclaration.elements {
                let caseName = element.name.text
                guard element.parameterClause == nil else {
                    throw macroFailure(.associatedValueEnum(caseName), at: element)
                }
                let value: String
                if isString {
                    if let rawValue = element.rawValue {
                        guard let literal = rawValue.value.as(StringLiteralExprSyntax.self),
                              literal.segments.count == 1,
                              case let .stringSegment(segment) = literal.segments.first else {
                            throw macroFailure(
                                .unsupportedEnumRepresentation,
                                at: rawValue.value
                            )
                        }
                        value = ".string(\(swiftLiteral(segment.content.text)))"
                    } else {
                        value = ".string(\(swiftLiteral(caseName)))"
                    }
                } else if let rawValue = element.rawValue?.value,
                          let integer = signedIntegerLiteral(rawValue) {
                    value = ".integer(\(integer))"
                    nextInteger = integer == .max ? nil : integer + 1
                } else if element.rawValue == nil, let integer = nextInteger {
                    value = ".integer(\(integer))"
                    nextInteger = integer == .max ? nil : integer + 1
                } else {
                    let node = element.rawValue.map { Syntax($0.value) }
                        ?? Syntax(element.name)
                    throw macroFailure(
                        .invalidIntegerEnumValue(caseName),
                        at: node
                    )
                }
                result.append(
                    .init(
                        name: caseName,
                        literalExpression: value,
                        documentationExpression:
                            documentation(of: caseDeclaration).declarationExpression,
                        sourceLocationExpression:
                            sourceLocationExpression(of: element, in: context)
                    )
                )
            }
        }
        return result
    }

    // MARK: Host types

    private static func host(
        _ declaration: some DeclGroupSyntax,
        rootType: String,
        isActor: Bool,
        context: some MacroExpansionContext
    ) throws -> ParsedExport.Host {
        var constructors: [String] = []
        var instanceMembers: [String] = []
        var staticMembers: [String] = []
        var instanceNames: Set<String> = []
        var staticNames: Set<String> = []
        var hasAsyncInitializer = false
        var staticCreateNode: Syntax?

        for member in declaration.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                guard isExported(initializer.modifiers, attributes: initializer.attributes) else {
                    continue
                }
                let parsed = try constructorExpression(
                    initializer,
                    rootType: rootType,
                    context: context
                )
                constructors.append(parsed.expression)
                hasAsyncInitializer = hasAsyncInitializer || parsed.isAsync
                continue
            }
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                guard isExported(function.modifiers, attributes: function.attributes) else {
                    continue
                }
                let isStatic = isTypeProperty(function.modifiers)
                if isStatic,
                   (renamedJavaScriptName(in: function.attributes)
                       ?? function.name.text) == "create" {
                    staticCreateNode = Syntax(function.name)
                }
                if isStatic {
                    let expression = try functionExpression(
                        function,
                        rootType: rootType,
                        isActor: isActor,
                        isStatic: true,
                        context: context,
                        exportedNames: &staticNames
                    )
                    staticMembers.append(expression)
                } else {
                    let expression = try functionExpression(
                        function,
                        rootType: rootType,
                        isActor: isActor,
                        isStatic: false,
                        context: context,
                        exportedNames: &instanceNames
                    )
                    instanceMembers.append(expression)
                }
                continue
            }
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                guard isExported(variable.modifiers, attributes: variable.attributes) else {
                    continue
                }
                let isStatic = isTypeProperty(variable.modifiers)
                if isStatic {
                    let expressions = try propertyExpressions(
                        variable,
                        rootType: rootType,
                        isActor: isActor,
                        isStatic: true,
                        context: context,
                        exportedNames: &staticNames
                    )
                    staticMembers.append(contentsOf: expressions)
                } else {
                    let expressions = try propertyExpressions(
                        variable,
                        rootType: rootType,
                        isActor: isActor,
                        isStatic: false,
                        context: context,
                        exportedNames: &instanceNames
                    )
                    instanceMembers.append(contentsOf: expressions)
                }
                continue
            }
            if let subscriptDeclaration = member.decl.as(SubscriptDeclSyntax.self),
               !hasAttribute("JavaScriptIgnore", on: subscriptDeclaration.attributes) {
                throw macroFailure(
                    .unsupportedProperty("subscript"),
                    at: subscriptDeclaration.subscriptKeyword
                )
            }
        }
        if hasAsyncInitializer, let staticCreateNode {
            throw macroFailure(.createConflict, at: staticCreateNode)
        }
        return .init(
            constructors: constructors,
            instanceMembers: instanceMembers,
            staticMembers: staticMembers
        )
    }

    private static func constructorExpression(
        _ initializer: InitializerDeclSyntax,
        rootType: String,
        context: some MacroExpansionContext
    ) throws -> (expression: String, isAsync: Bool) {
        guard initializer.genericParameterClause == nil,
              initializer.genericWhereClause == nil else {
            throw macroFailure(.genericInitializer, at: initializer.initKeyword)
        }
        guard initializer.optionalMark == nil else {
            throw macroFailure(.failableInitializer, at: initializer.optionalMark!)
        }
        let parsed = try parameters(
            initializer.signature.parameterClause.parameters,
            memberName: "init",
            isInitializer: true,
            context: context
        )
        let effects = initializer.signature.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrowing = effects?.throwsClause != nil
        try validateDocumentation(
            documentation(of: initializer),
            memberName: "init",
            parameterNames: parsed.names,
            at: initializer
        )
        let options = optionsExpression(
            parameterNames: parsed.names,
            parameterLocations: parsed.locations,
            documentation: documentation(of: initializer),
            isThrowing: isThrowing,
            sourceLocation: sourceLocationExpression(of: initializer, in: context)
        )
        let invocationPrefix = effectPrefix(isAsync: isAsync, isThrowing: isThrowing)
        let closureEffect = closureEffects(isAsync: isAsync, isThrowing: isThrowing)
        return (
            "JavaScriptHostConstructor<\(rootType)>(options: \(options), { (\(parsed.closureParameters.joined(separator: ", ")))\(closureEffect) -> \(rootType) in \(invocationPrefix)\(rootType)(\(parsed.callArguments.joined(separator: ", "))) })",
            isAsync
        )
    }

    private static func functionExpression(
        _ function: FunctionDeclSyntax,
        rootType: String,
        isActor: Bool,
        isStatic: Bool,
        context: some MacroExpansionContext,
        exportedNames: inout Set<String>
    ) throws -> String {
        guard function.genericParameterClause == nil,
              function.genericWhereClause == nil else {
            throw macroFailure(.genericMethod(function.name.text), at: function.name)
        }
        if case .identifier = function.name.tokenKind {
            // Valid Swift identifier; the final exported name is checked below.
        } else {
            throw macroFailure(.operatorMethod(function.name.text), at: function.name)
        }
        let swiftName = function.name.text
        let javaScriptName = renamedJavaScriptName(in: function.attributes) ?? swiftName
        try validateName(javaScriptName, at: function.name)
        try insert(
            javaScriptName,
            into: &exportedNames,
            surface: isStatic ? "static" : "instance",
            at: function.name
        )
        let parsed = try parameters(
            function.signature.parameterClause.parameters,
            memberName: swiftName,
            isInitializer: false,
            context: context
        )
        let documentation = documentation(of: function)
        try validateDocumentation(
            documentation,
            memberName: swiftName,
            parameterNames: parsed.names,
            at: function
        )
        let declaredAsync = function.signature.effectSpecifiers?.asyncSpecifier != nil
        let isAsync = declaredAsync || isActor
        let isThrowing = function.signature.effectSpecifiers?.throwsClause != nil
        let returnType = function.signature.returnClause?.type.trimmedDescription ?? "Void"
        let options = optionsExpression(
            parameterNames: parsed.names,
            parameterLocations: parsed.locations,
            documentation: documentation,
            isThrowing: isThrowing,
            sourceLocation: sourceLocationExpression(of: function, in: context)
        )
        let invocation = "\(effectPrefix(isAsync: isAsync, isThrowing: isThrowing))\(isStatic ? rootType : "root").\(swiftName)(\(parsed.callArguments.joined(separator: ", ")))"
        let effect = closureEffects(isAsync: isAsync, isThrowing: isThrowing)
        if isStatic {
            return "Function(\(swiftLiteral(javaScriptName)), options: \(options), { (\(parsed.closureParameters.joined(separator: ", ")))\(effect) -> \(returnType) in \(invocation) })"
        }
        let rootParameters = ["root: \(rootType)"] + parsed.closureParameters
        if isAsync {
            return "InstanceFunction<\(rootType)>(\(swiftLiteral(javaScriptName)), options: \(options), runtimeIsolated: { (_: isolated JavaScriptRuntime, \(rootParameters.joined(separator: ", ")))\(effect) -> \(returnType) in \(invocation) })"
        }
        return "InstanceFunction<\(rootType)>(\(swiftLiteral(javaScriptName)), options: \(options), { (\(rootParameters.joined(separator: ", ")))\(effect) -> \(returnType) in \(invocation) })"
    }

    private static func propertyExpressions(
        _ variable: VariableDeclSyntax,
        rootType: String,
        isActor: Bool,
        isStatic: Bool,
        context: some MacroExpansionContext,
        exportedNames: inout Set<String>
    ) throws -> [String] {
        var result: [String] = []
        for binding in variable.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                throw macroFailure(
                    .unsupportedProperty(binding.pattern.trimmedDescription),
                    at: binding.pattern
                )
            }
            let swiftName = pattern.identifier.text
            guard let annotation = binding.typeAnnotation else {
                throw macroFailure(
                    .propertyRequiresExplicitType(swiftName),
                    at: binding.pattern
                )
            }
            try validatePropertyAccessors(binding, name: swiftName)
            let javaScriptName = renamedJavaScriptName(in: variable.attributes) ?? swiftName
            try validateName(javaScriptName, at: pattern.identifier)
            try insert(
                javaScriptName,
                into: &exportedNames,
                surface: isStatic ? "static" : "instance",
                at: pattern.identifier
            )
            let docs = documentation(of: variable).declarationExpression
            let location = sourceLocationExpression(of: binding, in: context)
            let type = annotation.type.trimmedDescription
            let readOnly = isReadOnly(variable, binding: binding)
            if isStatic {
                if readOnly {
                    result.append(
                        "Property(\(swiftLiteral(javaScriptName)), documentation: \(docs), get: { () -> \(type) in \(rootType).\(swiftName) })"
                    )
                } else {
                    result.append(
                        "Property(\(swiftLiteral(javaScriptName)), documentation: \(docs), get: { () -> \(type) in \(rootType).\(swiftName) }, set: { (value: \(type)) in \(rootType).\(swiftName) = value })"
                    )
                }
            } else if isActor {
                let access = variable.bindingSpecifier.tokenKind == .keyword(.let)
                    ? "root.\(swiftName)"
                    : "await root.\(swiftName)"
                result.append(
                    "InstanceProperty<\(rootType)>(\(swiftLiteral(javaScriptName)), documentation: \(docs), sourceLocation: \(location), runtimeIsolatedGet: { (_: isolated JavaScriptRuntime, root: \(rootType)) async -> \(type) in \(access) })"
                )
            } else if readOnly {
                result.append(
                    "InstanceProperty<\(rootType)>(\(swiftLiteral(javaScriptName)), documentation: \(docs), sourceLocation: \(location), get: { (root: \(rootType)) -> \(type) in root.\(swiftName) })"
                )
            } else {
                result.append(
                    "InstanceProperty<\(rootType)>(\(swiftLiteral(javaScriptName)), documentation: \(docs), sourceLocation: \(location), get: { (root: \(rootType)) -> \(type) in root.\(swiftName) }, set: { (root: \(rootType), value: \(type)) in root.\(swiftName) = value })"
                )
            }
        }
        return result
    }

    // MARK: Host validation and rendering

    private struct ParsedParameters {
        let names: [String]
        let closureParameters: [String]
        let callArguments: [String]
        let locations: [String]
    }

    private static func parameters(
        _ parameters: FunctionParameterListSyntax,
        memberName: String,
        isInitializer: Bool,
        context: some MacroExpansionContext
    ) throws -> ParsedParameters {
        var names: [String] = []
        var closureParameters: [String] = []
        var callArguments: [String] = []
        var locations: [String] = []
        for (index, parameter) in parameters.enumerated() {
            let localToken = parameter.secondName ?? parameter.firstName
            let local = localToken.text == "_" ? "argument\(index)" : localToken.text
            if hasUnsupportedParameterFeatures(parameter) {
                let diagnostic: QuickJSKitMacroDiagnostic = isInitializer
                    ? .unsupportedInitializerParameter(local)
                    : .unsupportedMethodParameter(memberName, local)
                throw macroFailure(diagnostic, at: parameter)
            }
            try validateName(local, at: localToken)
            names.append(local)
            closureParameters.append("\(local): \(parameter.type.trimmedDescription)")
            locations.append(
                "\(swiftLiteral(local)): \(sourceLocationExpression(of: parameter, in: context))"
            )
            if parameter.firstName.text == "_" {
                callArguments.append(local)
            } else {
                callArguments.append("\(parameter.firstName.text): \(local)")
            }
        }
        return .init(
            names: names,
            closureParameters: closureParameters,
            callArguments: callArguments,
            locations: locations
        )
    }

    private static func optionsExpression(
        parameterNames: [String],
        parameterLocations: [String],
        documentation: ParsedDocumentation,
        isThrowing: Bool,
        sourceLocation: String
    ) -> String {
        let locations = parameterLocations.isEmpty
            ? "[:]"
            : "[\(parameterLocations.joined(separator: ", "))]"
        return ".init(parameterNames: [\(parameterNames.map(swiftLiteral).joined(separator: ", "))], documentation: \(documentation.functionExpression(parameterNames: parameterNames, isThrowing: isThrowing)), sourceLocation: \(sourceLocation), parameterSourceLocations: \(locations))"
    }

    private static func validateDocumentation(
        _ documentation: ParsedDocumentation,
        memberName: String,
        parameterNames: [String],
        at node: some SyntaxProtocol
    ) throws {
        if let duplicate = documentation.duplicateParameters.sorted().first {
            throw macroFailure(
                .duplicateDocumentationParameter(memberName, duplicate),
                at: node
            )
        }
        if let unknown = Set(documentation.parameters.keys)
            .subtracting(parameterNames)
            .sorted()
            .first {
            throw macroFailure(
                .unknownDocumentationParameter(memberName, unknown),
                at: node
            )
        }
    }

    private static func validatePropertyAccessors(
        _ binding: PatternBindingSyntax,
        name: String
    ) throws {
        guard let block = binding.accessorBlock else { return }
        switch block.accessors {
        case .getter:
            return
        case let .accessors(accessors):
            for accessor in accessors {
                if accessor.effectSpecifiers?.throwsClause != nil {
                    throw macroFailure(.throwingProperty(name), at: accessor)
                }
                let keyword = accessor.accessorSpecifier.text
                guard ["get", "set", "willSet", "didSet"].contains(keyword) else {
                    throw macroFailure(.unsupportedProperty(name), at: accessor)
                }
            }
        }
    }

    private static func isReadOnly(
        _ variable: VariableDeclSyntax,
        binding: PatternBindingSyntax
    ) -> Bool {
        if variable.bindingSpecifier.tokenKind == .keyword(.let)
            || hasAttribute("JavaScriptReadOnly", on: variable.attributes)
            || variable.modifiers.contains(where: {
                ["private", "fileprivate"].contains($0.name.text)
                    && $0.detail?.detail.text == "set"
            }) {
            return true
        }
        guard let block = binding.accessorBlock else { return false }
        switch block.accessors {
        case .getter:
            return true
        case let .accessors(accessors):
            return !accessors.contains(where: {
                ["set", "willSet", "didSet"].contains($0.accessorSpecifier.text)
            })
        }
    }

    private static func effectPrefix(
        isAsync: Bool,
        isThrowing: Bool
    ) -> String {
        if isAsync && isThrowing { return "try await " }
        if isAsync { return "await " }
        if isThrowing { return "try " }
        return ""
    }

    private static func closureEffects(
        isAsync: Bool,
        isThrowing: Bool
    ) -> String {
        let values = [isAsync ? "async" : nil, isThrowing ? "throws" : nil]
            .compactMap { $0 }
        return values.isEmpty ? "" : " \(values.joined(separator: " "))"
    }

    private static func validateName(
        _ name: String,
        at node: some SyntaxProtocol
    ) throws {
        guard isValidJavaScriptIdentifier(name) else {
            throw macroFailure(.invalidName(name), at: node)
        }
    }

    private static func insert(
        _ name: String,
        into names: inout Set<String>,
        surface: String,
        at node: some SyntaxProtocol
    ) throws {
        guard names.insert(name).inserted else {
            throw macroFailure(.duplicateName(name, surface), at: node)
        }
    }

    private static func isExported(
        _ modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax
    ) -> Bool {
        !modifiers.contains {
            ["private", "fileprivate"].contains($0.name.text)
        } && !hasAttribute("JavaScriptIgnore", on: attributes)
    }

    private static func isTypeProperty(
        _ modifiers: DeclModifierListSyntax
    ) -> Bool {
        modifiers.contains { ["static", "class"].contains($0.name.text) }
    }

    private static func firstPropertyWrapper(
        in attributes: AttributeListSyntax
    ) -> AttributeSyntax? {
        for element in attributes {
            guard case let .attribute(attribute) = element else { continue }
            let name = attributeName(attribute).split(separator: ".").last
            if name != "available" {
                return attribute
            }
        }
        return nil
    }

    private static func isStoredProperty(_ binding: PatternBindingSyntax) -> Bool {
        guard let block = binding.accessorBlock else { return true }
        switch block.accessors {
        case .getter:
            return false
        case let .accessors(accessors):
            return accessors.allSatisfy {
                ["willSet", "didSet"].contains($0.accessorSpecifier.text)
            }
        }
    }

    private static func unqualifiedInheritedTypeName(
        _ type: TypeSyntax
    ) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }
}
