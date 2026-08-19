# Security and Untrusted Code

QuickJSKit provides in-process resource controls. It is not an operating-system
sandbox.

## Understand the boundary

``JavaScriptRuntime/Configuration/restricted`` is a conservative starting
profile. It currently limits memory to 64 MiB, the JavaScript stack to 512 KiB,
active JavaScript execution to one second, live Swift host objects to 1,024,
and pending asynchronous host calls to 256.

QuickJS and exported Swift code still execute inside the application process.
If native memory corruption or application compromise is in scope, run the
embedding host in a separately sandboxed process.

## Minimize capabilities

Export the smallest capability-based Swift API possible. Filesystem, network,
credential, and process APIs define the authority available to scripts; they
are not implicitly provided by QuickJSKit.

Allowlist module specifiers and validate loader results. QuickJSKit includes no
implicit filesystem, network, package-manager, or npm loader. See
<doc:ModulesAndLoaders>.

## Bound execution and admission

Configure memory, stack, active execution, host-object, and pending-call limits
for the measured workload. Use Swift task cancellation for end-to-end
deadlines: an execution timeout covers active QuickJS work, not time suspended
in Swift bindings, loaders, or host Promise waiting.

Pending-call backpressure prevents unbounded task and Promise creation. It does
not cancel work that has already been admitted.

## Observe failures

Install an unhandled Promise rejection handler for background work and collect
``JavaScriptRuntime/resourceUsage()``. Treat resource failures, rejected
Promises, loader failures, and timeouts as observable application events.

## Keep dependencies current deliberately

Treat vendored QuickJS upgrades as security-sensitive dependency changes.
Review the upstream release, run the vendored-source verification, and qualify
the supported platform matrix before shipping.

## Related guides

- <doc:CancellationAndExecutionControl>
- <doc:ErrorsAndDiagnostics>
- <doc:PlatformSupport>
