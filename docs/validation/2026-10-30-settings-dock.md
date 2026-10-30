# Settings Dock lifecycle verification

Approved behavior: menu-only startup remains accessory. Explicitly opened settings temporarily use regular activation, retain the Dock entry when minimized, explicitly deminiaturize on application reopen even if the floating window is visible, and return to accessory after settings close. Internal synchronous rebuilds and immediate reopen coalesce the deferred demotion. Other windows cannot demote the settings Dock entry.

Native SettingsDockTests first failed4 assertions against old code. Product f35ffd2 passes the real AppKit activation-policy, minimize/restore, close/recreate, unrelated-window and queued close/immediate reopen cases. Nine related AppKit tests and full197Core+157AppKit/.NET/three Windows Release builds passed. macOS native CI41025631659 passed its complete job. Windows source is unchanged by this Mac fix; previous complete native floating-controls CI41022057506 remains relevant to its Windows candidate.

Clean local f35ffd2 candidate20261030-162032 passed137 source fingerprints, signed executable, official-runtime isolated startup/graceful exit and DMG verification. Transactional installation completed; installed executable matches the candidate and actual settings close/reopen works. Account and notification-policy fingerprints are unchanged. History is valid and previously verified historical read timestamps remain; its file hash changed while real reminders were naturally appended, so byte-identical history is not claimed. No artificial real notification or phone test was sent.

Dock's native automation surface timed out for name, bundle ID and path. Direct visual Dock-icon/physical Dock-click inspection is therefore not claimed; actual AppKit lifecycle assertions verify the activation/minimization/reopen contract. Spaces/full-screen and other device/OS coverage are not separately certified.

Fresh read-only review found no Important or Critical issue. Deferred Minor: the unrelated-window-close negative assertion could drain the main run loop before checking policy, to detect an incorrectly queued demotion more directly. The current production identity guard was reviewed, and the real lifecycle and close/reopen queue regressions passed; this test-hardening suggestion does not block the functional fix.

No product version change, merge or public release. Draft PR60 retains the update.
