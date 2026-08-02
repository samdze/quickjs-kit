internal import CQuickJS

internal enum BindingInvocation {
    case synchronous(ManagedQuickJSValue)
    case asynchronous(
        @Sendable (isolated JavaScriptRuntime) async -> BindingCompletion
    )
}

internal struct BindingResult: Sendable {
    internal let encode: @Sendable (QuickJSEngine) throws -> ManagedQuickJSValue
}

internal enum BindingCompletion: Sendable {
    case success(BindingResult)
    case failure(any Error)
}

internal typealias BindingSettlement = @Sendable (
    UInt64,
    BindingCompletion
) async -> Void

internal struct BoundFunction {
    internal let description: BindingDescription
    internal let invoke: @Sendable (
        isolated JavaScriptRuntime,
        QuickJSEngine,
        ManagedQuickJSValue,
        [ManagedQuickJSValue]
    ) throws -> BindingInvocation
    internal let settle: BindingSettlement
}

internal struct BindingDefinition: Sendable {
    internal let draft: BindingDraft
    internal let invoke: @Sendable (
        QuickJSEngine,
        [ManagedQuickJSValue]
    ) throws -> BindingInvocation

    internal func bind(
        location: BindingDescription.Location,
        order: UInt64,
        settle: @escaping BindingSettlement
    ) -> BoundFunction {
        BoundFunction(
            description: draft.finalize(location: location, order: order),
            invoke: { _, engine, _, arguments in
                try invoke(engine, arguments)
            },
            settle: settle
        )
    }
}

internal struct RuntimeLocalFunctionDefinition: Sendable {
    internal let draft: BindingDraft
    internal let invoke: @Sendable (
        isolated JavaScriptRuntime,
        QuickJSEngine,
        ManagedQuickJSValue,
        [ManagedQuickJSValue]
    ) throws -> BindingInvocation

    internal func bind(
        location: BindingDescription.Location,
        order: UInt64,
        settle: @escaping BindingSettlement
    ) -> BoundFunction {
        BoundFunction(
            description: draft.finalize(location: location, order: order),
            invoke: invoke,
            settle: settle
        )
    }
}

internal final class RegisteredBinding {
    internal let identifier: UInt64
    internal let name: String
    internal let function: BoundFunction?
    internal let root: (any AnyObject & Sendable)?
    internal let parentBindingIdentifier: UInt64?
    internal let runtimeRootIdentifier: UInt64?
    internal var exposedValue: ManagedQuickJSValue?
    internal var isActive = true
    internal var activeOperations: Set<UInt64> = []
    internal var childBindingIdentifiers: [UInt64] = []

    internal init(
        identifier: UInt64,
        name: String,
        function: BoundFunction?,
        root: (any AnyObject & Sendable)? = nil,
        parentBindingIdentifier: UInt64? = nil,
        runtimeRootIdentifier: UInt64? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.function = function
        self.root = root
        self.parentBindingIdentifier = parentBindingIdentifier
        self.runtimeRootIdentifier = runtimeRootIdentifier
    }
}

internal struct PendingSwiftPromise {
    internal let bindingIdentifier: UInt64
    internal let resolve: ManagedQuickJSValue
    internal let reject: ManagedQuickJSValue
    internal var task: Task<Void, Never>?
}

internal final class HostPromiseWaiter {
    internal let promise: ManagedQuickJSValue
    internal let poll: (QuickJSEngine, ManagedQuickJSValue) -> Bool
    internal let cancel: (QuickJSEngine) -> Void

    internal init(
        promise: ManagedQuickJSValue,
        poll: @escaping (QuickJSEngine, ManagedQuickJSValue) -> Bool,
        cancel: @escaping (QuickJSEngine) -> Void
    ) {
        self.promise = promise
        self.poll = poll
        self.cancel = cancel
    }
}

extension QuickJSEngine {
    private static var maximumBindingIdentifier: UInt64 { 9_007_199_254_740_991 }

    internal func registerGlobalBinding(
        named name: String,
        function: BoundFunction
    ) throws -> (UInt64, EngineJavaScriptValue) {
        let identifier = try allocateBindingIdentifier()
        let record = RegisteredBinding(
            identifier: identifier,
            name: name,
            function: function
        )
        swiftBindings[identifier] = record

        do {
            let rawFunction = try makeBoundFunction(
                bindingIdentifier: identifier,
                name: name,
                length: function.description.parameters.count
            )
            record.exposedValue = ManagedQuickJSValue(
                JS_DupValue(context, rawFunction.raw),
                in: context
            )
            let global = ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
            let status = name.withCString {
                JS_SetPropertyStr(context, global.raw, $0, JS_DupValue(context, rawFunction.raw))
            }
            guard status >= 0 else { throw extractException() }
            let decoded = try decodeUntyped(rawFunction)
            currentGlobalBindings[name] = identifier
            environmentGlobals[name] = RegisteredEnvironmentGlobal(
                bindingIdentifier: identifier,
                description: .function(EnvironmentFunctionDescription(function.description))
            )
            return (identifier, decoded)
        } catch {
            swiftBindings.removeValue(forKey: identifier)
            throw error
        }
    }

    internal func isBindingActive(_ identifier: UInt64) -> Bool {
        swiftBindings[identifier]?.isActive == true
    }

    internal func removeBinding(
        _ identifier: UInt64,
        cancellingInFlight: Bool
    ) throws -> Bool {
        guard let binding = swiftBindings[identifier], binding.isActive else { return false }
        binding.isActive = false

        for childIdentifier in binding.childBindingIdentifiers {
            _ = try removeBinding(childIdentifier, cancellingInFlight: cancellingInFlight)
        }

        if currentGlobalBindings[binding.name] == identifier {
            let global = ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
            let property = binding.name.withCString {
                JS_GetPropertyStr(context, global.raw, $0)
            }
            let current = ManagedQuickJSValue(property, in: context)
            if JS_IsException(property) != 0 { throw extractException() }
            if let exposed = binding.exposedValue,
               JS_StrictEq(context, current.raw, exposed.raw) != 0 {
                let atom = binding.name.withCString { JS_NewAtom(context, $0) }
                defer { JS_FreeAtom(context, atom) }
                let status = JS_DeleteProperty(context, global.raw, atom, Int32(JS_PROP_THROW))
                guard status >= 0 else { throw extractException() }
            }
            currentGlobalBindings.removeValue(forKey: binding.name)
        }
        if environmentGlobals[binding.name]?.bindingIdentifier == identifier {
            environmentGlobals.removeValue(forKey: binding.name)
        }

        if cancellingInFlight {
            for operationIdentifier in Array(binding.activeOperations) {
                cancelSwiftPromise(operationIdentifier)
            }
        }
        discardBindingIfFinished(binding)
        return true
    }

    internal func registerExport(
        named name: String,
        documentation: TypeScriptDocumentation?,
        root: (any AnyObject & Sendable)?,
        runtimeRootIdentifier: UInt64? = nil,
        members: [JavaScriptExportMemberDefinition],
        settle: @escaping BindingSettlement
    ) throws -> (UInt64, EngineJavaScriptValue) {
        guard !BindingValidation.hasDuplicateNames(members.map(\.name)) else {
            throw JavaScriptError(
                kind: .conversion,
                message: "An export cannot contain duplicate member names."
            )
        }

        let exportIdentifier = try allocateBindingIdentifier()
        let exportRecord = RegisteredBinding(
            identifier: exportIdentifier,
            name: name,
            function: nil,
            root: root,
            runtimeRootIdentifier: runtimeRootIdentifier
        )
        swiftBindings[exportIdentifier] = exportRecord
        var createdChildren: [UInt64] = []

        do {
            let object = ManagedQuickJSValue(JS_NewObject(context), in: context)
            if JS_IsException(object.raw) != 0 { throw extractException() }
            for (memberOrder, member) in members.enumerated() {
                switch member.storage {
                case let .function(definition):
                    let childIdentifier = try allocateBindingIdentifier()
                    let boundFunction = definition.bind(
                        location: .objectExport(name: name),
                        order: UInt64(memberOrder),
                        settle: settle
                    )
                    let child = RegisteredBinding(
                        identifier: childIdentifier,
                        name: member.name,
                        function: boundFunction,
                        root: root,
                        parentBindingIdentifier: exportIdentifier
                    )
                    swiftBindings[childIdentifier] = child
                    createdChildren.append(childIdentifier)
                    let rawFunction = try makeBoundFunction(
                        bindingIdentifier: childIdentifier,
                        name: member.name,
                        length: boundFunction.description.parameters.count
                    )
                    child.exposedValue = ManagedQuickJSValue(
                        JS_DupValue(context, rawFunction.raw),
                        in: context
                    )
                    try defineProperty(
                        member.name,
                        on: object.raw,
                        value: rawFunction.raw,
                        flags: 0
                    )
                case let .runtimeFunction(definition):
                    let childIdentifier = try allocateBindingIdentifier()
                    let boundFunction = definition.bind(
                        location: .objectExport(name: name),
                        order: UInt64(memberOrder),
                        settle: settle
                    )
                    let child = RegisteredBinding(
                        identifier: childIdentifier,
                        name: member.name,
                        function: boundFunction,
                        parentBindingIdentifier: exportIdentifier
                    )
                    swiftBindings[childIdentifier] = child
                    createdChildren.append(childIdentifier)
                    let rawFunction = try makeBoundFunction(
                        bindingIdentifier: childIdentifier,
                        name: member.name,
                        length: boundFunction.description.parameters.count
                    )
                    child.exposedValue = ManagedQuickJSValue(
                        JS_DupValue(context, rawFunction.raw),
                        in: context
                    )
                    try defineProperty(
                        member.name,
                        on: object.raw,
                        value: rawFunction.raw,
                        flags: 0
                    )
                case let .property(_, getter, setter):
                    let identifiers = try defineBoundProperty(
                        member.name,
                        on: object.raw,
                        getter: getter.bind(
                            location: .objectExport(name: name),
                            order: UInt64(memberOrder * 2),
                            settle: settle
                        ),
                        setter: setter?.bind(
                            location: .objectExport(name: name),
                            order: UInt64(memberOrder * 2 + 1),
                            settle: settle
                        ),
                        parentBindingIdentifier: exportIdentifier
                    )
                    createdChildren.append(contentsOf: identifiers)
                case let .runtimeProperty(_, getter, setter):
                    let identifiers = try defineBoundProperty(
                        member.name,
                        on: object.raw,
                        getter: getter.bind(
                            location: .objectExport(name: name),
                            order: UInt64(memberOrder * 2),
                            settle: settle
                        ),
                        setter: setter?.bind(
                            location: .objectExport(name: name),
                            order: UInt64(memberOrder * 2 + 1),
                            settle: settle
                        ),
                        parentBindingIdentifier: exportIdentifier
                    )
                    createdChildren.append(contentsOf: identifiers)
                case let .value(_, encode):
                    let value = try encode(self)
                    try defineProperty(
                        member.name,
                        on: object.raw,
                        value: value.raw,
                        flags: Int32(JS_PROP_ENUMERABLE)
                    )
                case let .liveValue(_, value):
                    let materialized = try materialize(value)
                    try defineProperty(
                        member.name,
                        on: object.raw,
                        value: materialized.raw,
                        flags: Int32(JS_PROP_ENUMERABLE)
                    )
                case .type:
                    throw JavaScriptError(
                        kind: .conversion,
                        message: "JavaScript types can be published only as globals or module exports."
                    )
                case .materializedHostType:
                    throw JavaScriptError(
                        kind: .conversion,
                        message: "JavaScript host types cannot be object members."
                    )
                }
            }
            exportRecord.childBindingIdentifiers = createdChildren
            exportRecord.exposedValue = ManagedQuickJSValue(
                JS_DupValue(context, object.raw),
                in: context
            )
            let global = ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
            let status = name.withCString {
                JS_SetPropertyStr(context, global.raw, $0, JS_DupValue(context, object.raw))
            }
            guard status >= 0 else { throw extractException() }
            let decoded = try decodeUntyped(object)
            currentGlobalBindings[name] = exportIdentifier
            environmentGlobals[name] = RegisteredEnvironmentGlobal(
                bindingIdentifier: exportIdentifier,
                description: .object(
                    name: name,
                    documentation: documentation,
                    members: members.map(\.environmentDescription)
                )
            )
            return (exportIdentifier, decoded)
        } catch {
            for identifier in createdChildren { swiftBindings.removeValue(forKey: identifier) }
            swiftBindings.removeValue(forKey: exportIdentifier)
            throw error
        }
    }

    internal func settleSwiftPromise(
        _ operationIdentifier: UInt64,
        with result: Result<ManagedQuickJSValue, any Error>
    ) {
        guard let pending = pendingSwiftPromises.removeValue(forKey: operationIdentifier) else {
            return
        }
        let argument: ManagedQuickJSValue
        let function: ManagedQuickJSValue
        switch result {
        case let .success(value):
            argument = value
            function = pending.resolve
        case let .failure(error):
            argument = makeJavaScriptError(from: error)
            function = pending.reject
        }
        _ = callRawFunction(function.raw, arguments: [argument.raw])
        finishOperation(operationIdentifier, bindingIdentifier: pending.bindingIdentifier)
    }

    internal func cancelSwiftPromise(_ operationIdentifier: UInt64) {
        guard let pending = pendingSwiftPromises.removeValue(forKey: operationIdentifier) else {
            return
        }
        pending.task?.cancel()
        let error = makeJavaScriptError(from: CancellationError())
        _ = callRawFunction(pending.reject.raw, arguments: [error.raw])
        finishOperation(operationIdentifier, bindingIdentifier: pending.bindingIdentifier)
    }

    internal func drainPendingJobs() throws {
        checkpointCountForTesting += 1
        var jobContext: OpaquePointer?
        while true {
            let status = JS_ExecutePendingJob(runtime, &jobContext)
            if status == 0 {
                pollHostPromiseWaiters()
                reportUnhandledRejections()
                return
            }
            if status < 0 { throw extractException() }
        }
    }

    internal func removeAllBindingsForTeardown() {
        for operationIdentifier in Array(pendingSwiftPromises.keys) {
            pendingSwiftPromises[operationIdentifier]?.task?.cancel()
        }
        pendingSwiftPromises.removeAll()
        for waiter in hostPromiseWaiters.values { waiter.cancel(self) }
        hostPromiseWaiters.removeAll()
        swiftBindings.removeAll()
        currentGlobalBindings.removeAll()
        environmentGlobals.removeAll()
        unhandledRejections.removeAll()
        observedPromiseAddresses.removeAll()
    }

    internal func promiseState(of value: ManagedQuickJSValue) -> QuickJSPromiseState? {
        promiseState(of: value.raw)
    }

    internal func promiseResult(of promise: ManagedQuickJSValue) -> ManagedQuickJSValue {
        ManagedQuickJSValue(JS_PromiseResult(context, promise.raw), in: context)
    }

    internal func markPromiseObserved(_ value: ManagedQuickJSValue) {
        guard promiseState(of: value) != nil else { return }
        let address = quickJSObjectAddress(value.raw)
        observedPromiseAddresses[address, default: 0] += 1
        unhandledRejections.removeValue(forKey: address)
    }

    internal func unmarkPromiseObserved(_ value: ManagedQuickJSValue) {
        guard promiseState(of: value) != nil else { return }
        unmarkPromiseObserved(at: quickJSObjectAddress(value.raw))
    }

    internal func unmarkPromiseObserved(at address: UInt) {
        guard let count = observedPromiseAddresses[address] else { return }
        if count <= 1 {
            observedPromiseAddresses.removeValue(forKey: address)
        } else {
            observedPromiseAddresses[address] = count - 1
        }
    }

    internal func recordPromiseRejection(
        promise: JSValue,
        reason: JSValue,
        isHandled: Bool
    ) {
        let address = quickJSObjectAddress(promise)
        if isHandled || observedPromiseAddresses[address] != nil {
            unhandledRejections.removeValue(forKey: address)
            return
        }
        unhandledRejections[address] = ManagedQuickJSValue(
            JS_DupValue(context, reason),
            in: context
        )
    }

    internal func allocateHostWaiterIdentifier() -> UInt64 {
        defer { nextHostWaiterIdentifier &+= 1 }
        return nextHostWaiterIdentifier
    }

    internal func installHostPromiseWaiter(
        _ waiter: HostPromiseWaiter,
        identifier: UInt64
    ) {
        hostPromiseWaiters[identifier] = waiter
        pollHostPromiseWaiters()
    }

    internal func cancelHostPromiseWaiter(_ identifier: UInt64) {
        guard let waiter = hostPromiseWaiters.removeValue(forKey: identifier) else { return }
        waiter.cancel(self)
    }

    internal func errorFromRejectedPromise(_ promise: ManagedQuickJSValue) -> JavaScriptError {
        let reason = promiseResult(of: promise)
        return errorFromRejectionReason(reason)
    }

    private func errorFromRejectionReason(_ reason: ManagedQuickJSValue) -> JavaScriptError {
        let rendered = string(from: reason.raw) ?? "A JavaScript promise was rejected."
        let name = propertyStringForBinding(named: "name", on: reason.raw)
        let message = propertyStringForBinding(named: "message", on: reason.raw) ?? rendered
        let stack = propertyStringForBinding(named: "stack", on: reason.raw)
        return JavaScriptError(
            kind: name == "CancellationError" ? .cancelled : .exception,
            name: name,
            message: message,
            stack: stack
        )
    }

    fileprivate func invokeBinding(
        identifier: UInt64,
        receiver: JSValue,
        arguments: UnsafeMutablePointer<JSValue>?,
        count: Int,
        isolatedRuntime: isolated JavaScriptRuntime
    ) -> JSValue {
        let isOutermostCallback = callbackDepth == 0
        if isOutermostCallback {
            // QuickJS's stack limit is measured from the outer JavaScript
            // entry. Swift Codable and generic callback frames are host stack,
            // not recursive JavaScript execution, and can legitimately exceed
            // that budget. Sync callbacks cannot re-enter JavaScript, so pause
            // the engine check while the host thunk runs and restore the exact
            // configured JavaScript limit before returning to QuickJS.
            JS_SetMaxStackSize(runtime, 0)
        }
        callbackDepth += 1
        defer {
            callbackDepth -= 1
            if isOutermostCallback {
                JS_SetMaxStackSize(runtime, maximumJavaScriptStackSize)
            }
        }
        guard let binding = swiftBindings[identifier],
              binding.isActive,
              let function = binding.function else {
            return throwJavaScriptError(
                name: "ReferenceError",
                message: "This Swift binding has been removed."
            )
        }

        let ownedArguments = (0..<count).map { index in
            ManagedQuickJSValue(
                JS_DupValue(context, arguments?[index] ?? quickJSUndefined()),
                in: context
            )
        }
        let ownedReceiver = ManagedQuickJSValue(
            JS_DupValue(context, receiver),
            in: context
        )
        do {
            switch try function.invoke(
                isolatedRuntime,
                self,
                ownedReceiver,
                ownedArguments
            ) {
            case let .synchronous(value):
                return JS_DupValue(context, value.raw)
            case let .asynchronous(operation):
                return try beginSwiftPromise(
                    binding: binding,
                    operation: operation,
                    isolatedRuntime: isolatedRuntime,
                    settle: function.settle
                )
            }
        } catch let decodingError as DecodingError {
            return throwJavaScriptError(
                name: "TypeError",
                message: String(describing: decodingError)
            )
        } catch {
            let value = makeJavaScriptError(from: error)
            return JS_Throw(context, JS_DupValue(context, value.raw))
        }
    }

    private func beginSwiftPromise(
        binding: RegisteredBinding,
        operation: @escaping @Sendable (
            isolated JavaScriptRuntime
        ) async -> BindingCompletion,
        isolatedRuntime: isolated JavaScriptRuntime,
        settle: @escaping BindingSettlement
    ) throws -> JSValue {
        if let limit = isolatedRuntime.configuration
            .maximumPendingHostCallCount,
           UInt64(pendingSwiftPromises.count) >= limit {
            throw JavaScriptError(
                kind: .resourceLimit,
                name: "RangeError",
                message: "The runtime pending host-call limit has been reached."
            )
        }
        let operationIdentifier = try allocateOperationIdentifier()
        var resolvingFunctions = [quickJSUndefined(), quickJSUndefined()]
        let promiseRaw = resolvingFunctions.withUnsafeMutableBufferPointer { buffer in
            JS_NewPromiseCapability(context, buffer.baseAddress)
        }
        if JS_IsException(promiseRaw) != 0 { throw extractException() }
        let promise = ManagedQuickJSValue(promiseRaw, in: context)
        let resolve = ManagedQuickJSValue(resolvingFunctions[0], in: context)
        let reject = ManagedQuickJSValue(resolvingFunctions[1], in: context)
        pendingSwiftPromises[operationIdentifier] = PendingSwiftPromise(
            bindingIdentifier: binding.identifier,
            resolve: resolve,
            reject: reject,
            task: nil
        )
        binding.activeOperations.insert(operationIdentifier)
        let task = Task { [weak isolatedRuntime] in
            guard let isolatedRuntime else { return }
            let completion = await isolatedRuntime.performBindingOperation(operation)
            await settle(operationIdentifier, completion)
        }
        pendingSwiftPromises[operationIdentifier]?.task = task
        return JS_DupValue(context, promise.raw)
    }

    private func finishOperation(_ identifier: UInt64, bindingIdentifier: UInt64) {
        guard let binding = swiftBindings[bindingIdentifier] else { return }
        binding.activeOperations.remove(identifier)
        discardBindingIfFinished(binding)
    }

    private func pollHostPromiseWaiters() {
        var completed: [UInt64] = []
        for (identifier, waiter) in hostPromiseWaiters {
            if waiter.poll(self, waiter.promise) {
                completed.append(identifier)
            }
        }
        for identifier in completed { hostPromiseWaiters.removeValue(forKey: identifier) }
    }

    private func reportUnhandledRejections() {
        guard let handler = unhandledRejectionHandler else {
            unhandledRejections.removeAll()
            return
        }
        let pending = unhandledRejections.sorted { $0.key < $1.key }
        unhandledRejections.removeAll()
        for (_, reason) in pending {
            handler(errorFromRejectionReason(reason))
        }
    }

    private func propertyStringForBinding(named name: String, on object: JSValue) -> String? {
        guard JS_IsObject(object) != 0 else { return nil }
        let raw = name.withCString { JS_GetPropertyStr(context, object, $0) }
        let property = ManagedQuickJSValue(raw, in: context)
        guard JS_IsException(raw) == 0, JS_IsString(raw) != 0 else {
            clearPendingException()
            return nil
        }
        return string(from: property.raw)
    }

    private func discardBindingIfFinished(_ binding: RegisteredBinding) {
        guard !binding.isActive,
              binding.activeOperations.isEmpty,
              binding.childBindingIdentifiers.isEmpty else { return }
        swiftBindings.removeValue(forKey: binding.identifier)
        if let parentIdentifier = binding.parentBindingIdentifier,
           let parent = swiftBindings[parentIdentifier] {
            parent.childBindingIdentifiers.removeAll { $0 == binding.identifier }
            discardBindingIfFinished(parent)
        }
        if let rootIdentifier = binding.runtimeRootIdentifier {
            releaseRuntimeRoot(rootIdentifier)
        }
    }

    internal func makeBoundFunction(
        bindingIdentifier: UInt64,
        name: String,
        length: Int
    ) throws -> ManagedQuickJSValue {
        let identifierValue = ManagedQuickJSValue(
            JS_NewInt64(context, Int64(bindingIdentifier)),
            in: context
        )
        var data = [identifierValue.raw]
        let raw = data.withUnsafeMutableBufferPointer { buffer in
            JS_NewCFunctionData(
                context,
                quickJSKitBindingTrampoline,
                Int32(length),
                0,
                1,
                buffer.baseAddress
            )
        }
        let function = ManagedQuickJSValue(raw, in: context)
        if JS_IsException(raw) != 0 { throw extractException() }
        let functionName = newString(name)
        try defineProperty("name", on: function.raw, value: functionName.raw, flags: 0)
        return function
    }

    internal func defineProperty(
        _ name: String,
        on object: JSValue,
        value: JSValue,
        flags: Int32
    ) throws {
        let status = name.withCString {
            JS_DefinePropertyValueStr(
                context,
                object,
                $0,
                JS_DupValue(context, value),
                flags | Int32(JS_PROP_THROW)
            )
        }
        guard status > 0 else { throw extractException() }
    }

    internal func defineBoundProperty(
        _ name: String,
        on object: JSValue,
        getter: BoundFunction,
        setter: BoundFunction?,
        parentBindingIdentifier: UInt64? = nil
    ) throws -> [UInt64] {
        var identifiers: [UInt64] = []
        do {
            let getterIdentifier = try allocateBindingIdentifier()
            let getterRecord = RegisteredBinding(
                identifier: getterIdentifier,
                name: name,
                function: getter,
                parentBindingIdentifier: parentBindingIdentifier
            )
            swiftBindings[getterIdentifier] = getterRecord
            identifiers.append(getterIdentifier)
            let getterValue = try makeBoundFunction(
                bindingIdentifier: getterIdentifier,
                name: "get \(name)",
                length: 0
            )
            getterRecord.exposedValue = ManagedQuickJSValue(
                JS_DupValue(context, getterValue.raw),
                in: context
            )

            var setterValue = ManagedQuickJSValue(quickJSUndefined(), in: context)
            if let setter {
                let setterIdentifier = try allocateBindingIdentifier()
                let setterRecord = RegisteredBinding(
                    identifier: setterIdentifier,
                    name: name,
                    function: setter,
                    parentBindingIdentifier: parentBindingIdentifier
                )
                swiftBindings[setterIdentifier] = setterRecord
                identifiers.append(setterIdentifier)
                setterValue = try makeBoundFunction(
                    bindingIdentifier: setterIdentifier,
                    name: "set \(name)",
                    length: 1
                )
                setterRecord.exposedValue = ManagedQuickJSValue(
                    JS_DupValue(context, setterValue.raw),
                    in: context
                )
            }

            let atom = name.withCString { JS_NewAtom(context, $0) }
            defer { JS_FreeAtom(context, atom) }
            let status = JS_DefinePropertyGetSet(
                context,
                object,
                atom,
                JS_DupValue(context, getterValue.raw),
                JS_DupValue(context, setterValue.raw),
                Int32(JS_PROP_ENUMERABLE)
            )
            guard status >= 0 else { throw extractException() }
            return identifiers
        } catch {
            for identifier in identifiers {
                swiftBindings.removeValue(forKey: identifier)
            }
            throw error
        }
    }

    internal func globalObject() -> ManagedQuickJSValue {
        ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
    }

    internal func throwJavaScriptError(name: String, message: String) -> JSValue {
        let error = makeJavaScriptError(name: name, message: message, swiftType: nil)
        return JS_Throw(context, JS_DupValue(context, error.raw))
    }

    internal func makeJavaScriptError(from error: any Error) -> ManagedQuickJSValue {
        if error is CancellationError {
            return makeJavaScriptError(
                name: "CancellationError",
                message: "The Swift task was cancelled.",
                swiftType: String(reflecting: type(of: error))
            )
        }
        if let error = error as? JavaScriptError {
            return makeJavaScriptError(
                name: error.name ?? "Error",
                message: error.message,
                swiftType: nil
            )
        }
        return makeJavaScriptError(
            name: "SwiftError",
            message: String(describing: error),
            swiftType: String(reflecting: type(of: error))
        )
    }

    private func makeJavaScriptError(
        name: String,
        message: String,
        swiftType: String?
    ) -> ManagedQuickJSValue {
        let error = ManagedQuickJSValue(JS_NewError(context), in: context)
        if ["TypeError", "RangeError", "ReferenceError", "SyntaxError"].contains(name) {
            let global = globalObject()
            let constructorRaw = name.withCString {
                JS_GetPropertyStr(context, global.raw, $0)
            }
            let constructor = ManagedQuickJSValue(constructorRaw, in: context)
            if JS_IsException(constructor.raw) == 0 {
                let prototypeRaw = "prototype".withCString {
                    JS_GetPropertyStr(context, constructor.raw, $0)
                }
                let prototype = ManagedQuickJSValue(prototypeRaw, in: context)
                if JS_IsException(prototype.raw) == 0 {
                    _ = JS_SetPrototype(context, error.raw, prototype.raw)
                } else {
                    clearPendingException()
                }
            } else {
                clearPendingException()
            }
        }
        let nameValue = newString(name)
        let messageValue = newString(message)
        try? defineProperty("name", on: error.raw, value: nameValue.raw, flags: Int32(JS_PROP_CONFIGURABLE))
        try? defineProperty("message", on: error.raw, value: messageValue.raw, flags: Int32(JS_PROP_CONFIGURABLE))
        if let swiftType {
            let swiftTypeValue = newString(swiftType)
            try? defineProperty("swiftType", on: error.raw, value: swiftTypeValue.raw, flags: 0)
        }
        return error
    }

    private func callRawFunction(_ function: JSValue, arguments: [JSValue]) -> Bool {
        var arguments = arguments
        let resultRaw = arguments.withUnsafeMutableBufferPointer { buffer in
            JS_Call(context, function, quickJSUndefined(), Int32(buffer.count), buffer.baseAddress)
        }
        let result = ManagedQuickJSValue(resultRaw, in: context)
        if JS_IsException(result.raw) != 0 {
            clearPendingException()
            return false
        }
        return true
    }

    internal func allocateBindingIdentifier() throws -> UInt64 {
        guard nextBindingIdentifier <= Self.maximumBindingIdentifier else {
            throw JavaScriptError(kind: .resourceLimit, message: "The binding identifier space is exhausted.")
        }
        defer { nextBindingIdentifier += 1 }
        return nextBindingIdentifier
    }

    private func allocateOperationIdentifier() throws -> UInt64 {
        guard nextOperationIdentifier < UInt64.max else {
            throw JavaScriptError(kind: .resourceLimit, message: "The asynchronous operation identifier space is exhausted.")
        }
        defer { nextOperationIdentifier += 1 }
        return nextOperationIdentifier
    }
}

private let quickJSKitBindingTrampoline: @convention(c) (
    OpaquePointer?,
    JSValue,
    Int32,
    UnsafeMutablePointer<JSValue>?,
    Int32,
    UnsafeMutablePointer<JSValue>?
) -> JSValue = { context, thisValue, argumentCount, arguments, _, functionData in
    guard let context,
          let functionData,
          let runtime = JS_GetRuntime(context),
          let opaque = JS_GetRuntimeOpaque(runtime) else {
        return quickJSUndefined()
    }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    guard let engine = bridge.engine,
          let owner = bridge.owner else { return quickJSUndefined() }
    var identifier: Int64 = 0
    guard JS_ToInt64(context, &identifier, functionData[0]) == 0, identifier > 0 else {
        engine.clearPendingException()
        return quickJSUndefined()
    }
    let argumentAddress = arguments.map { UInt(bitPattern: $0) }
    return owner.assumeIsolated { isolatedRuntime in
        let isolatedArguments = argumentAddress.flatMap {
            UnsafeMutablePointer<JSValue>(bitPattern: $0)
        }
        return isolatedRuntime.engine.invokeBinding(
            identifier: UInt64(identifier),
            receiver: thisValue,
            arguments: isolatedArguments,
            count: Int(argumentCount),
            isolatedRuntime: isolatedRuntime
        )
    }
}

internal let quickJSKitPromiseRejectionTracker: @convention(c) (
    OpaquePointer?,
    JSValue,
    JSValue,
    Int32,
    UnsafeMutableRawPointer?
) -> Void = { _, promise, reason, isHandled, opaque in
    guard let opaque else { return }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    bridge.engine?.recordPromiseRejection(
        promise: promise,
        reason: reason,
        isHandled: isHandled != 0
    )
}

internal let quickJSKitInterruptHandler: @convention(c) (
    OpaquePointer?,
    UnsafeMutableRawPointer?
) -> Int32 = { _, opaque in
    guard let opaque else { return 0 }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    return bridge.engine?.shouldInterrupt() == true ? 1 : 0
}
