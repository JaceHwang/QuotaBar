# Windows online update working-directory repair

Execute the user-approved minimal design on the beta.5 source base.

1. Add a failing regression for transient sharing violations and bounded retries. Keep other errors observable and preserve existing invalid-handle fallback and recovery tests.
2. Explicitly launch the copied helper from its own directory. Resolve update job paths before the helper detaches its working directory. Log the helper PID and both working directories. Retry only Windows sharing/lock violations for at most twenty 250 ms delays. Log source, destination and attempt.
3. Change the generic rollback text to describe update failure. Extend the native helper regression to launch both parent and helper with the active install as their inherited working directory.
4. Run Core tests, Windows app/setup builds, native UI tests and available governance checks. Review the diff independently.
5. Back up and bootstrap the repaired helper into this device's installed beta.4, then invoke its real online update entry point to upgrade to the official beta.5. Verify matching health/success receipts, exact payload hashes and preserved preferences. Deploy the beta.5 local development candidate containing the caller fix, helper protection and new messages, and verify Ready state.

The installed helper is copied from the old installation, so distributing a new package alone does not bootstrap the first update. Keep public release and local candidate evidence distinct.
