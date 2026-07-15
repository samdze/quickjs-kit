/// A runtime-bound encoder that creates native JavaScript values directly.
public struct JavaScriptEncoder: Sendable {
    /// The default maximum number of nested containers.
    public static let defaultMaximumNestingDepth = 64

    internal let runtime: JavaScriptRuntime

    /// The maximum number of nested keyed or unkeyed containers.
    ///
    /// Values below one are rejected with `EncodingError` when encoding begins.
    public var maximumNestingDepth: Int

    internal init(runtime: JavaScriptRuntime) {
        self.runtime = runtime
        self.maximumNestingDepth = Self.defaultMaximumNestingDepth
    }

    /// Encodes a Swift value directly into this encoder's JavaScript runtime.
    public func encode<T: Encodable & Sendable>(_ value: T) async throws -> JavaScriptValue {
        try await runtime.encode(value, maximumNestingDepth: maximumNestingDepth)
    }
}
