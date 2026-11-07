# Windows installer invalid-handle recovery

Implement in this session under the user's instruction to execute the repair.

## Scope

Preserve normal directory renames. For Windows error 0x80070006 only, persist a copy operation, copy and hash-verify every file, record completion, then remove the source. Resume or discard interrupted copies before recovering the existing installation journal. Validate every recorded path before deletion. Preserve existing install, rollback, uninstall, locking and registration behavior.

## Tasks

1. Add failure-injection regressions in the Core installer tests. Prove install, upgrade, startup rollback and uninstall fail with invalid directory handles before implementing the fallback.
2. Implement the recoverable copy operation and installation journal file compatibility. Test interrupted copy, interrupted source cleanup, failed restoration, retries, corrupt records and unrelated I/O errors.
3. Persist helper failure details with installation/startup stages. Run the full Core suite, Windows builds, governance and native tests. Report every failing check.
4. Package a local development candidate from the verified beta.4 package, update both application and setup Core DLLs and package provenance, retain a verified full backup, and install through the repaired executable. Verify the application reaches Ready and repeat the real helper health handshake on this device.

## Review focus

No source deletion before durable, verified destination. Failed backup copy must preserve the old target. Failed restore must retain recovery records and the sole valid backup. Read old journals. A restarted helper must recover copies even if the main installation journal was already removed. A failed health check must preserve the original diagnostic even if recovery also fails.

## Completion evidence

All four tasks completed on Windows. Full governance check local and final fast checks passed. Core regressions and independent review covered recovery cleanup and retained errors. The repaired executable installed the local candidate, and a local repaired-package fixture passed the actual helper entry point with health and success receipts. The unmodified official beta.4 probe exposed its old health-receipt rename failure and was rolled back. That failure is separately recorded. Final installation uses local-development provenance, exact file hashes, preserved preferences and a running Ready application. Mac and remote CI were not run. Source remains uncommitted on the repair branch.
