# Running Untrusted Code

Understand the boundary between in-process resource controls and isolation.

QuickJSKit and exported Swift code execute inside the application process.
``JavaScriptRuntime/Configuration/restricted`` is a conservative, customizable
starting point, not an operating-system sandbox. It currently limits memory to
64 MiB, the JavaScript stack to 512 KiB, active JavaScript execution to one
second, live Swift host objects to 1,024, and pending async host calls to 256.

For externally supplied scripts:

1. Run the entire embedding host in a separately sandboxed process when native
   memory corruption or application compromise is in scope.
2. Export the smallest capability-based Swift API possible. Exported filesystem,
   network, credential, and process APIs define the script's authority.
3. Allowlist module specifiers and validate loader results. QuickJSKit includes
   no implicit filesystem, network, or npm loader.
4. Configure memory, stack, execution, host-object, and pending-call limits for
   measured workloads.
5. Use Swift task cancellation for end-to-end deadlines. The JavaScript timeout
   counts only active parsing, execution, and immediately runnable jobs.
6. Observe rejected Promises and collect resource usage through
   ``JavaScriptRuntime/resourceUsage()``.
7. Treat QuickJS source upgrades as security-sensitive dependency changes.

An async Swift binding can wait on external work after JavaScript has stopped
executing. Pending-call backpressure prevents unbounded task and Promise
creation; it does not cancel already admitted work.
