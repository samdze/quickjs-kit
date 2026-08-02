internal import CQuickJS

private struct QuickJSKitClassIDs {
    let typeFunction: JSClassID
    let hostObject: JSClassID

    init() {
        var typeFunction = JSClassID()
        JS_NewClassID(&typeFunction)

        var hostObject = JSClassID()
        JS_NewClassID(&hostObject)

        self.typeFunction = typeFunction
        self.hostObject = hostObject
    }
}

// QuickJS allocates class identifiers from process-global state. Keep both
// QuickJSKit allocations in one Swift lazy initializer so Windows does not
// require QuickJS's POSIX-thread-backed Atomics configuration for this setup.
private let quickJSKitClassIDs = QuickJSKitClassIDs()

private struct QuickJSKitTypeFunctionPayload {
    let identifier: Int32
}

private struct QuickJSKitHostObjectPayload {
    let rootIdentifier: UInt64
    let typeIdentifier: Int32
    let swiftIdentity: ObjectIdentifier
}

internal struct HostObjectIdentityEntry {
    internal let value: JSValue
    internal let rootIdentifier: UInt64
}

internal enum RegisteredJavaScriptTypeDefinition {
    case value(AnyJavaScriptValueTypeDefinition)
    case host(AnyJavaScriptHostTypeDefinition)
}

internal final class RegisteredTypeFunction {
    internal let identifier: Int32
    internal let name: String
    internal let definition: RegisteredJavaScriptTypeDefinition
    internal let location: JavaScriptTypeLocation
    internal let function: ManagedQuickJSValue
    internal let prototype: ManagedQuickJSValue?
    internal let bindingIdentifiers: [UInt64]

    internal init(
        identifier: Int32,
        name: String,
        definition: RegisteredJavaScriptTypeDefinition,
        location: JavaScriptTypeLocation,
        function: ManagedQuickJSValue,
        prototype: ManagedQuickJSValue?,
        bindingIdentifiers: [UInt64] = []
    ) {
        self.identifier = identifier
        self.name = name
        self.definition = definition
        self.location = location
        self.function = function
        self.prototype = prototype
        self.bindingIdentifiers = bindingIdentifiers
    }
}

extension QuickJSEngine {
    internal func hostRootIdentifier(
        from value: JSValue,
        expectedTypeIdentifier: Int32
    ) throws -> UInt64 {
        guard let opaque = JS_GetOpaque(value, quickJSKitClassIDs.hostObject) else {
            throw JavaScriptError(
                kind: .conversion,
                message: "The value is not a registered Swift host object."
            )
        }
        let payload = opaque.assumingMemoryBound(
            to: QuickJSKitHostObjectPayload.self
        ).pointee
        guard payload.typeIdentifier == expectedTypeIdentifier else {
            throw JavaScriptError(
                kind: .conversion,
                message: "The Swift host object has the wrong registered type."
            )
        }
        return payload.rootIdentifier
    }

    private func ensureTypeFunctionClassIsRegistered() throws {
        guard JS_IsRegisteredClass(runtime, quickJSKitClassIDs.typeFunction) == 0 else {
            return
        }
        var definition = JSClassDef()
        definition.finalizer = quickJSKitTypeFunctionFinalizer
        definition.call = quickJSKitTypeFunctionCall
        let status = "QuickJSKit.Type".withCString { name in
            definition.class_name = name
            return JS_NewClass(runtime, quickJSKitClassIDs.typeFunction, &definition)
        }
        guard status >= 0 else {
            throw JavaScriptError(
                kind: .runtime,
                message: "QuickJS could not register the Swift type function class."
            )
        }
    }

    private func ensureHostObjectClassIsRegistered() throws {
        guard JS_IsRegisteredClass(runtime, quickJSKitClassIDs.hostObject) == 0 else {
            return
        }
        var hostDefinition = JSClassDef()
        hostDefinition.finalizer = quickJSKitHostObjectFinalizer
        let hostStatus = "QuickJSKit.HostObject".withCString { name in
            hostDefinition.class_name = name
            return JS_NewClass(runtime, quickJSKitClassIDs.hostObject, &hostDefinition)
        }
        guard hostStatus >= 0 else {
            throw JavaScriptError(
                kind: .runtime,
                message: "QuickJS could not register the Swift host object class."
            )
        }
    }

    internal func registerValueType(
        _ definition: AnyJavaScriptValueTypeDefinition,
        location: JavaScriptTypeLocation
    ) throws -> ManagedQuickJSValue {
        try ensureTypeFunctionClassIsRegistered()
        let identity = definition.swiftIdentity
        guard typeLocationsBySwiftIdentity[identity] == nil else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Swift type '\(definition.name)' is already registered in this runtime."
            )
        }
        guard nextTypeIdentifier < Int32.max else {
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "The JavaScript type identifier space is exhausted."
            )
        }
        let identifier = nextTypeIdentifier
        nextTypeIdentifier += 1

        let rawFunction = JS_NewObjectClass(
            context,
            Int32(bitPattern: quickJSKitClassIDs.typeFunction)
        )
        let function = ManagedQuickJSValue(rawFunction, in: context)
        guard JS_IsException(function.raw) == 0 else { throw extractException() }

        let payload = UnsafeMutablePointer<QuickJSKitTypeFunctionPayload>.allocate(capacity: 1)
        payload.initialize(to: QuickJSKitTypeFunctionPayload(identifier: identifier))
        JS_SetOpaque(function.raw, payload)

        let name = newString(definition.name)
        try defineProperty("name", on: function.raw, value: name.raw, flags: 0)

        let prototype: ManagedQuickJSValue?
        switch definition.kind {
        case .structure:
            let value = ManagedQuickJSValue(JS_NewObject(context), in: context)
            guard JS_IsException(value.raw) == 0 else { throw extractException() }
            guard JS_SetConstructor(context, function.raw, value.raw) >= 0 else {
                throw extractException()
            }
            guard JS_SetConstructorBit(context, function.raw, 1) >= 0 else {
                throw extractException()
            }
            prototype = value
        case let .enumeration(cases):
            for enumCase in cases {
                let value = try encodedLiteral(enumCase.value)
                try defineProperty(
                    enumCase.name,
                    on: function.raw,
                    value: value.raw,
                    flags: Int32(JS_PROP_ENUMERABLE)
                )
            }
            guard JS_PreventExtensions(context, function.raw) >= 0 else {
                throw extractException()
            }
            prototype = nil
        }

        let record = RegisteredTypeFunction(
            identifier: identifier,
            name: definition.name,
            definition: .value(definition),
            location: location,
            function: function,
            prototype: prototype
        )
        typeFunctions[identifier] = record
        typeLocationsBySwiftIdentity[identity] = location
        typeIdentifiersBySwiftIdentity[identity] = identifier
        return ManagedQuickJSValue(JS_DupValue(context, function.raw), in: context)
    }

    internal func publishGlobalValueType(
        _ definition: AnyJavaScriptValueTypeDefinition
    ) throws {
        let function = try registerValueType(definition, location: .global)
        do {
            let global = globalObject()
            try defineProperty(
                definition.name,
                on: global.raw,
                value: function.raw,
                flags: Int32(JS_PROP_ENUMERABLE)
            )
        } catch {
            unregisterJavaScriptType(for: definition.swiftIdentity)
            throw error
        }
        environmentGlobals[definition.name] = RegisteredEnvironmentGlobal(
            bindingIdentifier: nil,
            description: .type(
                AnyJavaScriptTypeDefinition.value(definition)
                    .environmentDescription(at: .global)
            )
        )
    }

    internal func publishGlobalHostType(
        _ definition: AnyJavaScriptHostTypeDefinition,
        function: ManagedQuickJSValue
    ) throws {
        do {
            let global = globalObject()
            try defineProperty(
                definition.name,
                on: global.raw,
                value: function.raw,
                flags: Int32(JS_PROP_ENUMERABLE)
            )
        } catch {
            unregisterJavaScriptType(for: definition.swiftIdentity)
            throw error
        }
        environmentGlobals[definition.name] = RegisteredEnvironmentGlobal(
            bindingIdentifier: nil,
            description: .type(definition.environmentDescription)
        )
    }

    internal func registerHostType(
        _ definition: AnyJavaScriptHostTypeDefinition,
        identifier: Int32,
        location: JavaScriptTypeLocation,
        instanceMembers: [JavaScriptExportMemberDefinition],
        settle: @escaping BindingSettlement
    ) throws -> ManagedQuickJSValue {
        try ensureTypeFunctionClassIsRegistered()
        try ensureHostObjectClassIsRegistered()
        guard typeLocationsBySwiftIdentity[definition.swiftIdentity] == location,
              typeFunctions[identifier] == nil else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "The reserved Swift host type is unavailable."
            )
        }
        guard !definition.constructors.isEmpty else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Host type '\(definition.name)' has no exported initializer."
            )
        }
        let rawFunction = JS_NewObjectClass(
            context,
            Int32(bitPattern: quickJSKitClassIDs.typeFunction)
        )
        let function = ManagedQuickJSValue(rawFunction, in: context)
        guard JS_IsException(rawFunction) == 0 else { throw extractException() }
        let payload = UnsafeMutablePointer<QuickJSKitTypeFunctionPayload>.allocate(capacity: 1)
        payload.initialize(to: .init(identifier: identifier))
        JS_SetOpaque(function.raw, payload)

        let prototype = ManagedQuickJSValue(JS_NewObject(context), in: context)
        guard JS_IsException(prototype.raw) == 0 else { throw extractException() }
        guard JS_SetConstructor(context, function.raw, prototype.raw) >= 0,
              JS_SetConstructorBit(context, function.raw, 1) >= 0 else {
            throw extractException()
        }
        let name = newString(definition.name)
        try defineProperty("name", on: function.raw, value: name.raw, flags: 0)

        var bindingIdentifiers: [UInt64] = []
        do {
            try installHostMembers(
                instanceMembers,
                on: prototype.raw,
                location: location,
                settle: settle,
                identifiers: &bindingIdentifiers
            )
            var staticMembers = definition.staticMembers
            if definition.constructors.contains(where: {
                if case .asynchronous = $0.invocation { true } else { false }
            }) {
                guard !staticMembers.contains(where: { $0.name == "create" }) else {
                    throw JavaScriptError(
                        kind: .conversion,
                        message: "Async host initializers conflict with static member 'create'."
                    )
                }
                staticMembers.insert(
                    try makeAsyncHostConstructorMember(
                        definition,
                        typeIdentifier: identifier
                    ),
                    at: 0
                )
            }
            try installHostMembers(
                staticMembers,
                on: function.raw,
                location: location,
                settle: settle,
                identifiers: &bindingIdentifiers
            )
        } catch {
            for bindingIdentifier in bindingIdentifiers {
                swiftBindings.removeValue(forKey: bindingIdentifier)
            }
            throw error
        }

        typeFunctions[identifier] = RegisteredTypeFunction(
            identifier: identifier,
            name: definition.name,
            definition: .host(definition),
            location: location,
            function: function,
            prototype: prototype,
            bindingIdentifiers: bindingIdentifiers
        )
        typeIdentifiersBySwiftIdentity[definition.swiftIdentity] = identifier
        return ManagedQuickJSValue(JS_DupValue(context, function.raw), in: context)
    }

    private func makeAsyncHostConstructorMember(
        _ definition: AnyJavaScriptHostTypeDefinition,
        typeIdentifier: Int32
    ) throws -> JavaScriptExportMemberDefinition {
        let constructors = definition.constructors.filter {
            if case .asynchronous = $0.invocation { true } else { false }
        }
        let parameterShapes = constructors.first?.draft.parameters.map(\.type) ?? []
        let parameterNames = constructors.first?.draft.parameters.map(\.name) ?? []
        let draft = BindingDraft(
            name: "create",
            parameters: zip(parameterNames, parameterShapes).map {
                BindingParameterDescription(name: $0, type: $1)
            },
            result: .unknown,
            effects: .init(isAsync: true, isThrowing: constructors.contains {
                $0.draft.effects.isThrowing
            }),
            documentation: constructors.first?.draft.documentation,
            sourceLocation: constructors.first?.draft.sourceLocation
        )
        let runtimeDefinition = RuntimeLocalFunctionDefinition(draft: draft) {
            _, engine, _, arguments in
            let candidates = constructors.filter {
                $0.draft.parameters.count == arguments.count
                    && $0.accepts(arguments, in: engine)
            }
            guard candidates.count == 1,
                  case let .asynchronous(makeOperation) = candidates[0].invocation else {
                throw JavaScriptError(
                    kind: .conversion,
                    message: hostConstructorSelectionMessage(
                        typeName: definition.name,
                        argumentCount: arguments.count,
                        matches: candidates.count,
                        candidates: constructors
                    )
                )
            }
            let operation = try makeOperation(engine, arguments)
            return .asynchronous { runtime in
                do {
                    let root = try await operation()
                    let identifier = try runtime.retainHostObject(root)
                    return .success(
                        BindingResult { engine in
                            do {
                                return try engine.makeRegisteredHostObject(
                                    rootIdentifier: identifier,
                                    typeIdentifier: typeIdentifier
                                )
                            } catch {
                                engine.releaseRuntimeRoot(identifier)
                                throw error
                            }
                        }
                    )
                } catch {
                    return .failure(error)
                }
            }
        }
        return JavaScriptExportMemberDefinition(
            name: "create",
            documentation: draft.documentation.map {
                TypeScriptDocumentation(summary: $0.summary)
            },
            validationMessage: nil,
            storage: .runtimeFunction(runtimeDefinition)
        )
    }

    internal func makeRegisteredHostObject(
        rootIdentifier: UInt64,
        typeIdentifier: Int32
    ) throws -> ManagedQuickJSValue {
        guard let record = typeFunctions[typeIdentifier],
              case .host = record.definition else {
            throw JavaScriptError(
                kind: .conversion,
                message: "The Swift host type is not registered in this runtime."
            )
        }
        guard let identity = hostObjectIdentitiesByRootIdentifier[rootIdentifier] else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "The Swift host object identity is unavailable."
            )
        }
        let raw = try makeHostObject(
            rootIdentifier: rootIdentifier,
            typeIdentifier: typeIdentifier,
            prototype: record.prototype,
            swiftIdentity: identity
        )
        return ManagedQuickJSValue(raw, in: context)
    }

    internal func reserveHostType(
        _ definition: AnyJavaScriptHostTypeDefinition,
        location: JavaScriptTypeLocation
    ) throws -> Int32 {
        guard typeLocationsBySwiftIdentity[definition.swiftIdentity] == nil else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Swift type '\(definition.name)' is already registered in this runtime."
            )
        }
        guard nextTypeIdentifier < Int32.max else {
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "The JavaScript type identifier space is exhausted."
            )
        }
        let identifier = nextTypeIdentifier
        nextTypeIdentifier += 1
        typeLocationsBySwiftIdentity[definition.swiftIdentity] = location
        return identifier
    }

    internal func cancelHostTypeReservation(
        _ definition: AnyJavaScriptHostTypeDefinition
    ) {
        unregisterJavaScriptType(for: definition.swiftIdentity)
    }

    internal func unregisterJavaScriptType(for swiftIdentity: ObjectIdentifier) {
        guard let identifier = typeIdentifiersBySwiftIdentity.removeValue(
            forKey: swiftIdentity
        ) else {
            typeLocationsBySwiftIdentity.removeValue(forKey: swiftIdentity)
            return
        }
        if let record = typeFunctions.removeValue(forKey: identifier) {
            for bindingIdentifier in record.bindingIdentifiers {
                swiftBindings.removeValue(forKey: bindingIdentifier)
            }
        }
        typeLocationsBySwiftIdentity.removeValue(forKey: swiftIdentity)
    }

    internal func hostTypeIdentifier<Root: JavaScriptHostTypeProviding>(
        for type: Root.Type
    ) throws -> Int32 {
        guard let identifier = typeIdentifiersBySwiftIdentity[ObjectIdentifier(type)] else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Swift host type '\(Root.javaScriptHostTypeDefinition.name)' is not registered in this runtime."
            )
        }
        return identifier
    }

    private func installHostMembers(
        _ members: [JavaScriptExportMemberDefinition],
        on object: JSValue,
        location: JavaScriptTypeLocation,
        settle: @escaping BindingSettlement,
        identifiers: inout [UInt64]
    ) throws {
        guard !BindingValidation.hasDuplicateNames(members.map(\.name)) else {
            throw JavaScriptError(
                kind: .conversion,
                message: "A host type cannot contain duplicate member names."
            )
        }
        let bindingLocation: BindingDescription.Location = switch location {
        case .global: .global
        case let .module(specifier): .module(specifier: specifier)
        }
        for (order, member) in members.enumerated() {
            if let message = member.validationMessage {
                throw JavaScriptError(kind: .conversion, message: message)
            }
            switch member.storage {
            case let .runtimeFunction(definition):
                let identifier = try allocateBindingIdentifier()
                let function = definition.bind(
                    location: bindingLocation,
                    order: UInt64(order),
                    settle: settle
                )
                let binding = RegisteredBinding(
                    identifier: identifier,
                    name: member.name,
                    function: function
                )
                swiftBindings[identifier] = binding
                identifiers.append(identifier)
                let value = try makeBoundFunction(
                    bindingIdentifier: identifier,
                    name: member.name,
                    length: function.description.parameters.count
                )
                binding.exposedValue = ManagedQuickJSValue(
                    JS_DupValue(context, value.raw),
                    in: context
                )
                try defineProperty(member.name, on: object, value: value.raw, flags: 0)
            case let .runtimeProperty(_, getter, setter):
                identifiers.append(contentsOf: try defineBoundProperty(
                    member.name,
                    on: object,
                    getter: getter.bind(
                        location: bindingLocation,
                        order: UInt64(order),
                        settle: settle
                    ),
                    setter: setter?.bind(
                        location: bindingLocation,
                        order: UInt64(order),
                        settle: settle
                    ),
                    parentBindingIdentifier: nil
                ))
            case let .function(definition):
                let identifier = try allocateBindingIdentifier()
                let function = definition.bind(
                    location: bindingLocation,
                    order: UInt64(order),
                    settle: settle
                )
                let binding = RegisteredBinding(
                    identifier: identifier,
                    name: member.name,
                    function: function
                )
                swiftBindings[identifier] = binding
                identifiers.append(identifier)
                let value = try makeBoundFunction(
                    bindingIdentifier: identifier,
                    name: member.name,
                    length: function.description.parameters.count
                )
                binding.exposedValue = ManagedQuickJSValue(
                    JS_DupValue(context, value.raw),
                    in: context
                )
                try defineProperty(member.name, on: object, value: value.raw, flags: 0)
            case let .property(_, getter, setter):
                identifiers.append(contentsOf: try defineBoundProperty(
                    member.name,
                    on: object,
                    getter: getter.bind(
                        location: bindingLocation,
                        order: UInt64(order),
                        settle: settle
                    ),
                    setter: setter?.bind(
                        location: bindingLocation,
                        order: UInt64(order),
                        settle: settle
                    ),
                    parentBindingIdentifier: nil
                ))
            case .value, .liveValue, .type, .materializedHostType:
                throw JavaScriptError(
                    kind: .conversion,
                    message: "Host type members must be functions or live properties."
                )
            }
        }
    }

    fileprivate func invokeTypeFunction(
        identifier: Int32,
        newTarget: JSValue,
        arguments: UnsafeMutablePointer<JSValue>?,
        count: Int,
        flags: Int32,
        isolatedRuntime: isolated JavaScriptRuntime
    ) -> JSValue {
        guard let record = typeFunctions[identifier] else {
            return throwJavaScriptError(
                name: "ReferenceError",
                message: "This Swift type is no longer registered."
            )
        }
        let isConstructor = flags & Int32(JS_CALL_FLAG_CONSTRUCTOR) != 0
        let expectsConstructor: Bool
        switch record.definition {
        case let .value(definition):
            switch definition.kind {
            case .structure: expectsConstructor = true
            case .enumeration: expectsConstructor = false
            }
        case .host:
            expectsConstructor = true
        }
        guard isConstructor == expectsConstructor else {
            return throwJavaScriptError(
                name: "TypeError",
                message: expectsConstructor
                    ? "\(record.name) must be called with new."
                    : "\(record.name) is a validator and cannot be called with new."
            )
        }
        if isConstructor, JS_StrictEq(context, newTarget, record.function.raw) == 0 {
            return throwJavaScriptError(
                name: "TypeError",
                message: "Swift value types cannot be subclassed."
            )
        }
        do {
            switch record.definition {
            case let .value(definition):
                guard count == 1 else {
                    return throwJavaScriptError(
                        name: "TypeError",
                        message: "\(record.name) expects exactly one argument."
                    )
                }
                let input = ManagedQuickJSValue(
                    JS_DupValue(context, arguments?[0] ?? quickJSUndefined()),
                    in: context
                )
                let result = try definition.construct(self, input)
                if let prototype = record.prototype {
                    guard JS_SetPrototype(context, result.raw, prototype.raw) >= 0 else {
                        throw extractException()
                    }
                }
                return JS_DupValue(context, result.raw)
            case let .host(definition):
                let ownedArguments = (0..<count).map { index in
                    ManagedQuickJSValue(
                        JS_DupValue(
                            context,
                            arguments?[index] ?? quickJSUndefined()
                        ),
                        in: context
                    )
                }
                let candidates = definition.constructors.filter {
                    guard $0.draft.parameters.count == count else { return false }
                    if case .synchronous = $0.invocation {
                        return $0.accepts(ownedArguments, in: self)
                    }
                    return false
                }
                guard candidates.count == 1,
                      case let .synchronous(invoke) = candidates[0].invocation else {
                    return throwJavaScriptError(
                        name: "TypeError",
                        message: hostConstructorSelectionMessage(
                            typeName: record.name,
                            argumentCount: count,
                            matches: candidates.count,
                            candidates: definition.constructors.filter {
                                if case .synchronous = $0.invocation { true } else { false }
                            }
                        )
                    )
                }
                let rootIdentifier = try invoke(
                    isolatedRuntime,
                    self,
                    ownedArguments
                )
                do {
                    return try makeHostObject(
                        rootIdentifier: rootIdentifier,
                        typeIdentifier: identifier,
                        prototype: record.prototype,
                        swiftIdentity: try isolatedRuntime.runtimeRootObjectIdentifier(
                            rootIdentifier
                        )
                    )
                } catch {
                    isolatedRuntime.releaseRuntimeRoot(rootIdentifier)
                    throw error
                }
            }
        } catch let error as JavaScriptError where error.kind == .resourceLimit {
            return throwJavaScriptError(
                name: "RangeError",
                message: error.message
            )
        } catch let error as DecodingError {
            return throwJavaScriptError(
                name: "TypeError",
                message: String(describing: error)
            )
        } catch {
            return throwJavaScriptError(
                name: "TypeError",
                message: String(describing: error)
            )
        }
    }

    private func makeHostObject(
        rootIdentifier: UInt64,
        typeIdentifier: Int32,
        prototype: ManagedQuickJSValue?,
        swiftIdentity: ObjectIdentifier
    ) throws -> JSValue {
        if let existing = hostObjectsBySwiftIdentity[swiftIdentity] {
            releaseRuntimeRoot(rootIdentifier)
            return JS_DupValue(context, existing.value)
        }
        let raw = JS_NewObjectClass(
            context,
            Int32(bitPattern: quickJSKitClassIDs.hostObject)
        )
        let object = ManagedQuickJSValue(raw, in: context)
        guard JS_IsException(raw) == 0 else { throw extractException() }
        let payload = UnsafeMutablePointer<QuickJSKitHostObjectPayload>.allocate(capacity: 1)
        payload.initialize(
            to: .init(
                rootIdentifier: rootIdentifier,
                typeIdentifier: typeIdentifier,
                swiftIdentity: swiftIdentity
            )
        )
        JS_SetOpaque(object.raw, payload)
        if let prototype {
            guard JS_SetPrototype(context, object.raw, prototype.raw) >= 0 else {
                payload.deinitialize(count: 1)
                payload.deallocate()
                JS_SetOpaque(object.raw, nil)
                throw extractException()
            }
        }
        // This is a borrowed weak entry: the native finalizer removes it before
        // QuickJS releases the object storage. It never owns a reference count.
        hostObjectsBySwiftIdentity[swiftIdentity] = HostObjectIdentityEntry(
            value: object.raw,
            rootIdentifier: rootIdentifier
        )
        return JS_DupValue(context, object.raw)
    }


    fileprivate func removeHostObjectIdentity(
        _ identity: ObjectIdentifier,
        rootIdentifier: UInt64
    ) {
        guard hostObjectsBySwiftIdentity[identity]?.rootIdentifier
            == rootIdentifier else { return }
        hostObjectsBySwiftIdentity.removeValue(forKey: identity)
    }

    private func encodedLiteral(
        _ literal: TypeScriptLiteral
    ) throws -> ManagedQuickJSValue {
        switch literal {
        case let .string(value):
            return try encode(
                value,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
        case let .integer(value):
            return try encode(
                value,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
        }
    }

}

private func hostConstructorSelectionMessage(
    typeName: String,
    argumentCount: Int,
    matches: Int,
    candidates: [AnyJavaScriptHostConstructor]
) -> String {
    let signatures = candidates
        .map { constructor in
            let parameters = constructor.draft.parameters.map { parameter in
                "\(parameter.name): \(String(describing: parameter.type))"
            }
            return "\(typeName)(\(parameters.joined(separator: ", ")))"
        }
        .joined(separator: ", ")
    let reason = matches == 0 ? "No initializer matches" : "The initializer is ambiguous for"
    return "\(reason) \(argumentCount) argument(s). Candidates: \(signatures)."
}

private let quickJSKitTypeFunctionFinalizer: @convention(c) (
    OpaquePointer?,
    JSValue
) -> Void = { _, value in
    guard let opaque = JS_GetOpaque(value, quickJSKitClassIDs.typeFunction) else {
        return
    }
    let payload = opaque.assumingMemoryBound(to: QuickJSKitTypeFunctionPayload.self)
    payload.deinitialize(count: 1)
    payload.deallocate()
}

private let quickJSKitHostObjectFinalizer: @convention(c) (
    OpaquePointer?,
    JSValue
) -> Void = { runtime, value in
    guard let opaque = JS_GetOpaque(value, quickJSKitClassIDs.hostObject) else {
        return
    }
    let payload = opaque.assumingMemoryBound(to: QuickJSKitHostObjectPayload.self)
    let rootIdentifier = payload.pointee.rootIdentifier
    let swiftIdentity = payload.pointee.swiftIdentity
    payload.deinitialize(count: 1)
    payload.deallocate()
    guard let runtime,
          let bridgeOpaque = JS_GetRuntimeOpaque(runtime) else { return }
    let bridge = Unmanaged<QuickJSRuntimeBridge>
        .fromOpaque(bridgeOpaque)
        .takeUnretainedValue()
    bridge.engine?.removeHostObjectIdentity(
        swiftIdentity,
        rootIdentifier: rootIdentifier
    )
    guard let owner = bridge.owner else { return }
    owner.assumeIsolated { runtime in
        runtime.releaseRuntimeRoot(rootIdentifier)
    }
}

private let quickJSKitTypeFunctionCall: @convention(c) (
    OpaquePointer?,
    JSValue,
    JSValue,
    Int32,
    UnsafeMutablePointer<JSValue>?,
    Int32
) -> JSValue = { context, function, newTarget, count, arguments, flags in
    guard let context,
          let runtime = JS_GetRuntime(context),
          let bridgeOpaque = JS_GetRuntimeOpaque(runtime),
          let payloadOpaque = JS_GetOpaque(function, quickJSKitClassIDs.typeFunction) else {
        return quickJSUndefined()
    }
    let bridge = Unmanaged<QuickJSRuntimeBridge>
        .fromOpaque(bridgeOpaque)
        .takeUnretainedValue()
    let payload = payloadOpaque.assumingMemoryBound(
        to: QuickJSKitTypeFunctionPayload.self
    )
    guard let owner = bridge.owner else { return quickJSUndefined() }
    let identifier = payload.pointee.identifier
    let argumentAddress = arguments.map { UInt(bitPattern: $0) }
    return owner.assumeIsolated { isolatedRuntime in
        let isolatedArguments = argumentAddress.flatMap {
            UnsafeMutablePointer<JSValue>(bitPattern: $0)
        }
        return isolatedRuntime.engine.invokeTypeFunction(
            identifier: identifier,
            newTarget: newTarget,
            arguments: isolatedArguments,
            count: Int(count),
            flags: flags,
            isolatedRuntime: isolatedRuntime
        )
    }
}
