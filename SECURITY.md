# Security Policy

## Supported versions

Before the first public release, security fixes are made on the default branch.
After release, the latest tagged version will receive security fixes; older
minor versions may be addressed when the impact justifies it.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's **Report a
vulnerability** security-advisory form once the repository is published. If
private advisories are unavailable, contact the repository owner privately and
include “quickshell-share-picker security” in the subject. Do not include
sensitive exploit details in a public issue.

Useful reports include:

- affected version or commit;
- reproduction steps and environment;
- expected and observed behavior;
- impact, especially any stdout protocol injection, unsafe file handling,
  cross-invocation interference, or command execution; and
- a suggested fix, if available.

Receipt and remediation timing depend on maintainer availability and issue
severity; this project does not promise a fixed response SLA. Coordinated
public disclosure is preferred after a fix is available.

## Security boundaries

The picker treats `XDPH_WINDOW_SHARING_LIST`, QML-visible window metadata,
`slurp` output, and the private result file as untrusted data. The wrapper:

- never evaluates those values as shell code;
- uses argument arrays for subprocesses;
- creates a unique mode-0700 runtime directory with mode-0600 data files;
- validates one complete protocol line before emitting it;
- sends diagnostics only to stderr;
- bounds the Quickshell lifetime; and
- removes runtime data through exit and signal traps.

The picker does not provide sandboxing. Quickshell, XDPH, Hyprland, and `slurp`
run with the user's privileges and remain part of the trusted computing base.
