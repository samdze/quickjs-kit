/// A stable, engine-independent summary of JavaScript heap usage.
public struct JavaScriptMemoryUsage: Sendable, Hashable {
    /// Bytes currently reserved by the QuickJS allocator.
    public let allocatedBytes: UInt64

    /// The configured allocation limit, or `nil` when unlimited.
    public let allocationLimit: UInt64?

    /// QuickJS's estimate of bytes used by live JavaScript data.
    public let usedBytes: UInt64

    internal init(
        allocatedBytes: UInt64,
        allocationLimit: UInt64?,
        usedBytes: UInt64
    ) {
        self.allocatedBytes = allocatedBytes
        self.allocationLimit = allocationLimit
        self.usedBytes = usedBytes
    }
}
