extension JavaScriptRuntime {
    internal func call<each Argument>(
        _ function: JavaScriptReference,
        arguments: repeat each Argument,
        options: JavaScriptExecutionOptions
    ) throws -> JavaScriptValue
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable {
        try engine.withExecution(options: options) {
            try validate(function, expected: .function)
            let arguments = try encodeArguments(repeat each arguments)
            return try makeValue(
                engine.call(
                    function.identifier,
                    receiverIdentifier: nil,
                    arguments: arguments
                )
            )
        }
    }

    internal func call<each Argument, Result>(
        _ function: JavaScriptReference,
        arguments: repeat each Argument,
        as type: Result.Type,
        options: JavaScriptExecutionOptions
    ) async throws -> Result
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable,
          Result: Decodable & Sendable {
        let raw = try engine.withExecution(options: options) {
            try validate(function, expected: .function)
            let arguments = try encodeArguments(repeat each arguments)
            let raw = try engine.callRaw(
                function.identifier,
                receiverIdentifier: nil,
                arguments: arguments
            )
            engine.markPromiseObserved(raw)
            return raw
        }
        return try await decodeAwaitingPromise(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            alreadyObserved: true,
            jobsAlreadyDrained: true,
            options: options
        )
    }

    internal func call<each Argument, Result>(
        _ function: JavaScriptReference,
        on receiver: JavaScriptReference,
        arguments: repeat each Argument,
        as type: Result.Type,
        options: JavaScriptExecutionOptions
    ) async throws -> Result
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable,
          Result: Decodable & Sendable {
        let raw = try engine.withExecution(options: options) {
            try validate(function, expected: .function)
            try validate(receiver)
            let arguments = try encodeArguments(repeat each arguments)
            let raw = try engine.callRaw(
                function.identifier,
                receiverIdentifier: receiver.identifier,
                arguments: arguments
            )
            engine.markPromiseObserved(raw)
            return raw
        }
        return try await decodeAwaitingPromise(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            alreadyObserved: true,
            jobsAlreadyDrained: true,
            options: options
        )
    }

    internal func call(
        _ function: JavaScriptReference,
        arguments: [JavaScriptValue],
        receiver: JavaScriptReference?,
        options: JavaScriptExecutionOptions
    ) throws -> JavaScriptValue {
        try engine.withExecution(options: options) {
            try validate(function, expected: .function)
            if let receiver { try validate(receiver) }
            for argument in arguments { try validate(argument) }
            let rawArguments = try arguments.map(engine.materialize)
            return try makeValue(
                engine.call(
                    function.identifier,
                    receiverIdentifier: receiver?.identifier,
                    arguments: rawArguments
                )
            )
        }
    }

    private func encodeArguments<each Argument>(
        _ arguments: repeat each Argument
    ) throws -> [ManagedQuickJSValue]
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable {
        var result: [ManagedQuickJSValue] = []
        for argument in repeat each arguments {
            result.append(
                try engine.encode(
                    argument,
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
            )
        }
        return result
    }
}
