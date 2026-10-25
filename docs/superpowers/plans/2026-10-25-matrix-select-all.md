# Matrix select-all implementation plan

**Goal:** Add one select-all shortcut and make all18 category/channel rules selected for fresh installations.

**Direction:** Continue approved A and explicit mockup opt-out. Put Select all in the matrix card toolbar. It changes all18 rules, including disabled columns, while retaining channel masters, threshold, pause, credentials and history.

**Compatibility:** New installs use all-selected rules; existing policy files and legacy preference migration remain unchanged. Masters remain independent. No schema/version change, permission prompt or phone test on selection.

- [x] Add regression tests for bulk selection, retained channel states and fresh versus saved/legacy policy.
- [x] Implement shared all-selected rule factory, platform first-run routing and native shortcut.
- [ ] Run focused and full checks, independent review; build and install candidate serially and verify actual UI.
