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
        let isActor = declaration.is(ActorDeclSyntax.self)
        if let classDeclaration = declaration.as(ClassDeclSyntax.self),
           !classDeclaration.modifiers.contains(where: { $0.name.text == "final" }) {
            throw QuickJSKitMacroError("@JavaScriptExport requires a final class or an actor.")
        }
        guard isActor || declaration.is(ClassDeclSyntax.self) else {
            throw QuickJSKitMacroError("@JavaScriptExport supports actors and final classes.")
        }

        var expressions: [String] = []
        var exportedNames: Set<String> = []
        for member in declaration.memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                guard !isExcluded(function.modifiers),
                      !hasAttribute("JavaScriptIgnore", on: function.attributes) else {
                    continue
                }
                expressions.append(
                    try functionExpression(
                        function,
                        rootType: name,
                        isActor: isActor,
                        context: context,
                        exportedNames: &exportedNames
                    )
                )
            } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                guard !isExcluded(variable.modifiers),
                      !hasAttribute("JavaScriptIgnore", on: variable.attributes) else {
                    continue
                }
                expressions.append(contentsOf: try propertyExpressions(
                    variable,
                    rootType: name,
                    isActor: isActor,
                    context: context,
                    exportedNames: &exportedNames
                ))
            }
        }

        let docs = documentation(of: declaration).declarationExpression
        let body = expressions.map { "            \($0)" }.joined(separator: "\n")
        return [
            DeclSyntax(stringLiteral: "public static let javaScriptExportDocumentation: TypeScriptDocumentation? = \(docs)"),
            DeclSyntax(stringLiteral: "public static let javaScriptExportSourceLocation: TypeScriptSourceLocation? = \(sourceLocationExpression(of: declaration, in: context))"),
            DeclSyntax(stringLiteral: """
            public static let javaScriptExportDefinition = JavaScriptRuntimeTemplate.InstanceExport<\(name)> {
            \(body)
            }
            """),
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        [try ExtensionDeclSyntax("extension \(type.trimmed): JavaScriptExportProviding {}")]
    }

    private static func functionExpression(
        _ function: FunctionDeclSyntax,
        rootType: String,
        isActor: Bool,
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
        let invocation = "\(invocationPrefix)root.\(swiftName)(\(callArguments.joined(separator: ", ")))"
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
            if isActor {
                result.append(
                    "InstanceProperty<\(rootType)>(\(swiftLiteral(javascriptName)), documentation: \(docs), sourceLocation: \(sourceLocation), runtimeIsolatedGet: { (_: isolated JavaScriptRuntime, root: \(rootType)) async -> \(type) in await root.\(swiftName) })"
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
