import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct JavaScriptExportMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let name = try declarationName(declaration)
        if declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) {
            return try valueTypeMembers(
                declaration,
                name: name,
                context: context
            )
        }
        let isActor = declaration.is(ActorDeclSyntax.self)
        if let classDeclaration = declaration.as(ClassDeclSyntax.self),
           !classDeclaration.modifiers.contains(where: { $0.name.text == "final" }) {
            throw QuickJSKitMacroError("@JavaScriptExport requires a final class or an actor.")
        }
        guard isActor || declaration.is(ClassDeclSyntax.self) else {
            throw QuickJSKitMacroError("@JavaScriptExport supports actors and final classes.")
        }

        var expressions: [String] = []
        var staticExpressions: [String] = []
        var constructorExpressions: [String] = []
        var exportedNames: Set<String> = []
        for member in declaration.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                guard !isPrivate(initializer.modifiers),
                      !hasAttribute("JavaScriptIgnore", on: initializer.attributes) else {
                    continue
                }
                constructorExpressions.append(
                    try constructorExpression(
                        initializer,
                        rootType: name,
                        context: context
                    )
                )
            } else if let function = member.decl.as(FunctionDeclSyntax.self) {
                guard !isPrivate(function.modifiers),
                      !hasAttribute("JavaScriptIgnore", on: function.attributes) else {
                    continue
                }
                let isStatic = function.modifiers.contains(where: {
                    ["static", "class"].contains($0.name.text)
                })
                let expression = try functionExpression(
                        function,
                        rootType: name,
                        isActor: isActor,
                        isStatic: isStatic,
                        context: context,
                        exportedNames: &exportedNames
                    )
                if isStatic {
                    staticExpressions.append(expression)
                } else {
                    expressions.append(expression)
                }
            } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                guard !isPrivate(variable.modifiers),
                      !hasAttribute("JavaScriptIgnore", on: variable.attributes) else {
                    continue
                }
                let isStatic = variable.modifiers.contains(where: {
                    ["static", "class"].contains($0.name.text)
                })
                let generated = try propertyExpressions(
                    variable,
                    rootType: name,
                    isActor: isActor,
                    isStatic: isStatic,
                    context: context,
                    exportedNames: &exportedNames
                )
                if isStatic {
                    staticExpressions.append(contentsOf: generated)
                } else {
                    expressions.append(contentsOf: generated)
                }
            }
        }

        let docs = documentation(of: declaration).declarationExpression
        let body = expressions.map { "            \($0)" }.joined(separator: "\n")
        let constructors = constructorExpressions.joined(separator: ",\n                ")
        let staticBody = staticExpressions.map { "            \($0)" }
            .joined(separator: "\n")
        return [
            DeclSyntax(stringLiteral: "public static let javaScriptHostTypeName = \(swiftLiteral(renamedJavaScriptName(in: declaration.attributes) ?? name))"),
            DeclSyntax(stringLiteral: "public static let javaScriptHostTypeScope: TypeScriptDeclarationScope? = \(scopeExpression(node))"),
            DeclSyntax(stringLiteral: "public static let javaScriptExportDocumentation: TypeScriptDocumentation? = \(docs)"),
            DeclSyntax(stringLiteral: "public static let javaScriptExportSourceLocation: TypeScriptSourceLocation? = \(sourceLocationExpression(of: declaration, in: context))"),
            DeclSyntax(stringLiteral: """
            public static let javaScriptExportDefinition = JavaScriptRuntimeTemplate.InstanceExport<\(name)> {
            \(body)
            }
            """),
            DeclSyntax(stringLiteral: """
            public static let javaScriptHostTypeDefinition = JavaScriptHostTypeDefinition<\(name)>(
                name: javaScriptHostTypeName,
                documentation: javaScriptExportDocumentation,
                sourceLocation: javaScriptExportSourceLocation,
                scope: javaScriptHostTypeScope,
                instanceMembers: javaScriptExportDefinition,
                constructors: [
                    \(constructors)
                ]
            ) {
            \(staticBody)
            }
            """),
        ]
    }

    private static func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains {
            ["private", "fileprivate"].contains($0.name.text)
        }
    }

    private static func scopeExpression(_ node: AttributeSyntax) -> String {
        guard case let .argumentList(arguments) = node.arguments,
              let argument = arguments.first else { return "nil" }
        return argument.expression.trimmedDescription
    }

    private static func constructorExpression(
        _ initializer: InitializerDeclSyntax,
        rootType: String,
        context: some MacroExpansionContext
    ) throws -> String {
        guard initializer.optionalMark == nil,
              initializer.genericParameterClause == nil else {
            throw QuickJSKitMacroError(
                "Exported initializers cannot be failable or generic."
            )
        }
        let parameters = initializer.signature.parameterClause.parameters
        var closureParameters: [String] = []
        var parameterNames: [String] = []
        var parameterLocations: [String] = []
        var arguments: [String] = []
        for (index, parameter) in parameters.enumerated() {
            guard parameter.defaultValue == nil,
                  parameter.ellipsis == nil,
                  !parameter.type.trimmedDescription.hasPrefix("inout ") else {
                throw QuickJSKitMacroError(
                    "Exported initializers cannot use default, variadic, or inout parameters."
                )
            }
            let localToken = parameter.secondName ?? parameter.firstName
            let local = localToken.text == "_" ? "argument\(index)" : localToken.text
            let exposed = local
            closureParameters.append("\(local): \(parameter.type.trimmedDescription)")
            parameterNames.append(exposed)
            parameterLocations.append(
                "\(swiftLiteral(exposed)): \(sourceLocationExpression(of: parameter, in: context))"
            )
            if parameter.firstName.text == "_" {
                arguments.append(local)
            } else {
                arguments.append("\(parameter.firstName.text): \(local)")
            }
        }
        let effects = initializer.signature.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrowing = effects?.throwsClause != nil
        let docs = documentation(of: initializer)
        let locationDictionary = parameterLocations.isEmpty
            ? "[:]"
            : "[\(parameterLocations.joined(separator: ", "))]"
        let options = ".init(parameterNames: [\(parameterNames.map(swiftLiteral).joined(separator: ", "))], documentation: \(docs.functionExpression(parameterNames: parameterNames, isThrowing: isThrowing)), sourceLocation: \(sourceLocationExpression(of: initializer, in: context)), parameterSourceLocations: \(locationDictionary))"
        let invocationPrefix = isAsync && isThrowing ? "try await "
            : isAsync ? "await " : isThrowing ? "try " : ""
        let effectsText = [isAsync ? "async" : nil, isThrowing ? "throws" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        let closureEffects = effectsText.isEmpty ? "" : " \(effectsText)"
        return "JavaScriptHostConstructor<\(rootType)>(options: \(options), { (\(closureParameters.joined(separator: ", ")))\(closureEffects) -> \(rootType) in \(invocationPrefix)\(rootType)(\(arguments.joined(separator: ", "))) })"
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        if declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self) {
            var extensions = try JavaScriptValueSchemaMacro.expansion(
                of: node,
                attachedTo: declaration,
                providingExtensionsOf: type,
                conformingTo: protocols,
                in: context
            )
            extensions.append(
                try ExtensionDeclSyntax(
                    "extension \(type.trimmed): JavaScriptValueTypeProviding {}"
                )
            )
            return extensions
        }
        return [
            try ExtensionDeclSyntax(
                "extension \(type.trimmed): JavaScriptExportProviding, JavaScriptHostTypeProviding {}"
            ),
        ]
    }

    private static func valueTypeMembers(
        _ declaration: some DeclGroupSyntax,
        name: String,
        context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        for member in declaration.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self),
               !hasAttribute("JavaScriptIgnore", on: function.attributes) {
                throw QuickJSKitMacroError(
                    "Struct and enum methods are not live JavaScript members; add @JavaScriptIgnore or export a final class or actor."
                )
            }
        }
        let javascriptName = renamedJavaScriptName(in: declaration.attributes) ?? name
        let docs = documentation(of: declaration).declarationExpression
        let location = sourceLocationExpression(of: declaration, in: context)
        let kind: String
        if let enumDeclaration = declaration.as(EnumDeclSyntax.self) {
            let cases = try valueEnumCases(enumDeclaration, context: context)
            kind = ".enumeration(cases: [\(cases.joined(separator: ", "))])"
        } else {
            kind = ".structure"
        }
        return [
            DeclSyntax(stringLiteral: """
            public static let javaScriptValueTypeDefinition = JavaScriptValueTypeDefinition<Self>(
                name: \(swiftLiteral(javascriptName)),
                documentation: \(docs),
                sourceLocation: \(location),
                kind: \(kind)
            )
            """),
        ]
    }

    private static func valueEnumCases(
        _ declaration: EnumDeclSyntax,
        context: some MacroExpansionContext
    ) throws -> [String] {
        let inherited = declaration.inheritanceClause?.inheritedTypes.map {
            $0.type.trimmedDescription
        } ?? []
        let isString = inherited.contains("String")
        let isInteger = inherited.contains("Int")
        guard isString || isInteger else {
            throw QuickJSKitMacroError(
                "@JavaScriptExport enums require a raw String or Int representation."
            )
        }
        var nextInteger: Int64? = 0
        var result: [String] = []
        for member in declaration.memberBlock.members {
            guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in cases.elements {
                guard element.parameterClause == nil else {
                    throw QuickJSKitMacroError(
                        "Associated-value enums are not runtime-publishable."
                    )
                }
                let caseName = element.name.text
                let literal: String
                if isString {
                    if let raw = element.rawValue?.value.as(StringLiteralExprSyntax.self),
                       raw.segments.count == 1,
                       case let .stringSegment(segment) = raw.segments.first {
                        literal = ".string(\(swiftLiteral(segment.content.text)))"
                    } else {
                        literal = ".string(\(swiftLiteral(caseName)))"
                    }
                } else if let raw = element.rawValue?.value,
                          let integer = signedIntegerLiteral(raw) {
                    nextInteger = integer == .max ? nil : integer + 1
                    literal = ".integer(\(integer))"
                } else if element.rawValue == nil, let integer = nextInteger {
                    literal = ".integer(\(integer))"
                    nextInteger = integer == .max ? nil : integer + 1
                } else {
                    throw QuickJSKitMacroError(
                        "Raw Int enum values must be integer literals within Int64, and implicit values cannot follow Int64.max."
                    )
                }
                result.append(
                    ".init(\(swiftLiteral(caseName)), value: \(literal), documentation: \(documentation(of: cases).declarationExpression), sourceLocation: \(sourceLocationExpression(of: element, in: context)))"
                )
            }
        }
        return result
    }

    private static func functionExpression(
        _ function: FunctionDeclSyntax,
        rootType: String,
        isActor: Bool,
        isStatic: Bool,
        context: some MacroExpansionContext,
        exportedNames: inout Set<String>
    ) throws -> String {
        guard function.genericParameterClause == nil else {
            throw QuickJSKitMacroError("Exported methods cannot be generic.")
        }
        let swiftName = function.name.text
        let javascriptName = renamedJavaScriptName(in: function.attributes) ?? swiftName
        guard exportedNames.insert(javascriptName).inserted else {
            throw QuickJSKitMacroError("Duplicate JavaScript export name '\(javascriptName)'.")
        }

        let parameters = function.signature.parameterClause.parameters
        var closureParameters = ["root: \(rootType)"]
        var parameterNames: [String] = []
        var parameterLocations: [String] = []
        var callArguments: [String] = []
        for (index, parameter) in parameters.enumerated() {
            guard parameter.defaultValue == nil,
                  parameter.ellipsis == nil,
                  !parameter.type.trimmedDescription.hasPrefix("inout ") else {
                throw QuickJSKitMacroError(
                    "Exported method '\(swiftName)' uses an unsupported parameter feature."
                )
            }
            let localToken = parameter.secondName ?? parameter.firstName
            let local = localToken.text == "_" ? "argument\(index)" : localToken.text
            let exposed = localToken.text == "_" ? "argument\(index)" : local
            parameterNames.append(exposed)
            parameterLocations.append(
                "\(swiftLiteral(exposed)): \(sourceLocationExpression(of: parameter, in: context))"
            )
            closureParameters.append("\(local): \(parameter.type.trimmedDescription)")
            if parameter.firstName.text == "_" {
                callArguments.append(local)
            } else {
                callArguments.append("\(parameter.firstName.text): \(local)")
            }
        }

        let effects = function.signature.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil || isActor
        let isThrowing = effects?.throwsClause != nil
        let returnType = function.signature.returnClause?.type.trimmedDescription ?? "Void"
        let effectText = [isAsync ? "async" : nil, isThrowing ? "throws" : nil]
            .compactMap { $0 }.joined(separator: " ")
        let closureEffect = effectText.isEmpty ? "" : " \(effectText)"
        let invocationPrefix = isThrowing && isAsync ? "try await "
            : isThrowing ? "try " : isAsync ? "await " : ""
        let receiver = isStatic ? rootType : "root"
        let invocation = "\(invocationPrefix)\(receiver).\(swiftName)(\(callArguments.joined(separator: ", ")))"
        let docs = documentation(of: function)
        if let duplicate = docs.duplicateParameters.sorted().first {
            throw QuickJSKitMacroError(
                "Documentation for exported method '\(swiftName)' describes parameter '\(duplicate)' more than once."
            )
        }
        if let unknown = Set(docs.parameters.keys)
            .subtracting(parameterNames)
            .sorted()
            .first {
            throw QuickJSKitMacroError(
                "Documentation for exported method '\(swiftName)' refers to unknown parameter '\(unknown)'."
            )
        }
        let locationDictionary = parameterLocations.isEmpty
            ? "[:]"
            : "[\(parameterLocations.joined(separator: ", "))]"
        let options = ".init(parameterNames: [\(parameterNames.map(swiftLiteral).joined(separator: ", "))], documentation: \(docs.functionExpression(parameterNames: parameterNames, isThrowing: isThrowing)), sourceLocation: \(sourceLocationExpression(of: function, in: context)), parameterSourceLocations: \(locationDictionary))"
        if isStatic {
            let parameters = Array(closureParameters.dropFirst())
            return "Function(\(swiftLiteral(javascriptName)), options: \(options), { (\(parameters.joined(separator: ", ")))\(closureEffect) -> \(returnType) in \(invocation) })"
        }
        let closure = "{ (\(closureParameters.joined(separator: ", ")))\(closureEffect) -> \(returnType) in \(invocation) }"
        if isAsync {
            return "InstanceFunction<\(rootType)>(\(swiftLiteral(javascriptName)), options: \(options), runtimeIsolated: { (_: isolated JavaScriptRuntime, \(closureParameters.joined(separator: ", ")))\(closureEffect) -> \(returnType) in \(invocation) })"
        }
        return "InstanceFunction<\(rootType)>(\(swiftLiteral(javascriptName)), options: \(options), \(closure))"
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
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let annotation = binding.typeAnnotation else {
                throw QuickJSKitMacroError("Exported properties require an explicit type.")
            }
            let swiftName = pattern.identifier.text
            let javascriptName = renamedJavaScriptName(in: variable.attributes) ?? swiftName
            guard exportedNames.insert(javascriptName).inserted else {
                throw QuickJSKitMacroError("Duplicate JavaScript export name '\(javascriptName)'.")
            }
            let docs = documentation(of: variable).declarationExpression
            let sourceLocation = sourceLocationExpression(of: binding, in: context)
            let type = annotation.type.trimmedDescription
            if isStatic {
                let isReadOnly = variable.bindingSpecifier.tokenKind == .keyword(.let)
                    || hasAttribute("JavaScriptReadOnly", on: variable.attributes)
                if isReadOnly {
                    result.append(
                        "Property(\(swiftLiteral(javascriptName)), documentation: \(docs), get: { () -> \(type) in \(rootType).\(swiftName) })"
                    )
                } else {
                    result.append(
                        "Property(\(swiftLiteral(javascriptName)), documentation: \(docs), get: { () -> \(type) in \(rootType).\(swiftName) }, set: { (value: \(type)) in \(rootType).\(swiftName) = value })"
                    )
                }
                continue
            }
            if isActor {
                let access = variable.bindingSpecifier.tokenKind == .keyword(.let)
                    ? "root.\(swiftName)"
                    : "await root.\(swiftName)"
                result.append(
                    "InstanceProperty<\(rootType)>(\(swiftLiteral(javascriptName)), documentation: \(docs), sourceLocation: \(sourceLocation), runtimeIsolatedGet: { (_: isolated JavaScriptRuntime, root: \(rootType)) async -> \(type) in \(access) })"
                )
                continue
            }
            let isReadOnly = variable.bindingSpecifier.tokenKind == .keyword(.let)
                || hasAttribute("JavaScriptReadOnly", on: variable.attributes)
                || variable.modifiers.contains(where: {
                    ["private", "fileprivate"].contains($0.name.text)
                        && $0.detail?.detail.text == "set"
                })
            if isReadOnly {
                result.append(
                    "InstanceProperty<\(rootType)>(\(swiftLiteral(javascriptName)), documentation: \(docs), sourceLocation: \(sourceLocation), get: { (root: \(rootType)) -> \(type) in root.\(swiftName) })"
                )
            } else {
                result.append(
                    "InstanceProperty<\(rootType)>(\(swiftLiteral(javascriptName)), documentation: \(docs), sourceLocation: \(sourceLocation), get: { (root: \(rootType)) -> \(type) in root.\(swiftName) }, set: { (root: \(rootType), value: \(type)) in root.\(swiftName) = value })"
                )
            }
        }
        return result
    }
}

public struct MarkerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
