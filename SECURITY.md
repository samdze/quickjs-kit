# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub Security
Advisories for this repository. Do not open a public issue for an unpatched
vulnerability. Include the affected revision, platform, reproduction steps,
impact, and any known mitigations.

Maintainers will acknowledge a complete report, investigate it, coordinate a
fix and disclosure, and credit the reporter when requested. Timelines depend on
severity and cross-platform validation requirements.

Repository administrators must enable GitHub private vulnerability reporting.
This repository file documents the policy but does not enable that setting.

## Supported versions

QuickJSKit is currently pre-release. Security fixes are made on the main
development line until the first supported release is published. Supported
release lines will be listed here when they exist.

## Trust boundary

QuickJSKit embeds QuickJS and exported Swift code in the application process.
It is not an operating-system sandbox. Memory limits, stack limits, execution
timeouts, host-object limits, and host-call backpressure reduce denial-of-service
risk but cannot isolate native memory corruption or an overly powerful exported
Swift API.

Applications running hostile scripts should use a separately sandboxed process,
expose a minimal capability-based Swift API, allowlist module resolution, apply
resource limits, and validate all data crossing the process boundary.

See the DocC guide `Running Untrusted Code` for detailed guidance.
