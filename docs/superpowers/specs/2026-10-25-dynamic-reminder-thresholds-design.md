# Dynamic reminder thresholds — approved A

## User-selected direction

User selected A compact editable threshold chips after three generated previews. Top masters are 气泡通知 / 系统通知 / 手机推送通知. Matrix column headings stay compact 气泡 / 系统 / 手机, each with its own Select all shortcut; no global select-all button. A column shortcut selects only its category rules and is disabled when its master is off.

Visual constraints: preserve current native AppKit/WPF shell, compact spacing, blue actions, light/dark themes and three languages. Numeric editable chips include a unit and delete affordance, plus an add action; chips wrap within the category label area. Visible rows in order: quota depleted, quota restored, quota low, Bank expiry, software update. Low immediately precedes Bank. Each category has one channel checkbox per column, independent of threshold count. Test notification remains immediately under the matrix and uses masters.

## Behavior

- Bank is one visible category, with editable/addable/removable hour thresholds. Default [72,24]. Integers1–8760 hours; deduplicate and sort descending.
- Low quota has editable/addable/removable percentage thresholds. Migrate the existing scalar as a one-element list; fresh default [20]. Integers1–99; deduplicate and sort descending.
- Allow up to32 values per category. Removing the last value disables that category's events while retaining its channel selections; show an empty-state hint and add action. Cancel/invalid/duplicate input does not change saved state.
- Each threshold can trigger once per applicable credit or quota period. A sample crossing several thresholds emits only the most urgent eligible threshold and consumes the less urgent crossings. Existing depletion/recovery rules remain independent.
- Editing/adding/enabling thresholds establishes a baseline; no historical replay. Preserve consumed state across restart and edits. Account rotation, metadata validation, missing Bank fields, receipt bounds and complete-inventory baseline behavior remain intact.
- New installs select every visible category/channel rule; only the bubble master is initially enabled. Never silently enable system/mobile or prompt on select-all.

## Compatibility and data

Keep existing six serialized NotificationCategory values for old readers/tests, but present legacy Bank72/24 as one UI group. Add optional lowRemainingThresholds, bankExpiryHours and bankThresholdChannels fields to policy schema1. Missing fields use scalar low threshold and [72,24] legacy behavior; malformed explicit fields fail closed for that category, not a hidden default. Normalize count/ranges deterministically.

Per-hour Bank channel mappings preserve old72/24 channel differences. A merged checkbox shows mixed if only some configured thresholds select that channel. Clicking that checkbox unifies that channel across all Bank thresholds; the per-column Select all does the same for its own channel. Adding a Bank threshold inherits the intersection of current Bank channel selections, so legacy mixed settings never silently widen mobile delivery. Editing a threshold retains its channel mapping. Removing a threshold removes its override.

Add optional reminderThreshold metadata to ExperienceNotification and delivery snapshots. Policy eligibility for low messages requires the threshold still configured; Bank eligibility uses the exact hour's channel mapping. Removed/edited thresholds cancel pending old deliveries, while originally eligible channels never expand on reenable. Existing scalar/category-only messages retain legacy behavior.

## Engineering calls

Bank detection accepts configurable thresholds; receipt.stage remains the most urgent consumed hour, retaining old receipts. Low detection gains a list-based overload while retaining the scalar overload for compatibility. Engines preserve receipt/recovery behavior and emit stable threshold-specific identities. Separate core implementers own Bank and warning engines; coordinator owns policy, routing, controllers and UI. All implementation is in the existing feature worktree, no version changes, merge or public release.

## Acceptance

Shared Swift/.NET fixtures cover72→24→12,20→10, skips/coalescing, duplicates/empty/invalid lists, edits, restart, old receipts and complete inventories. Policy tests cover old scalar and split Bank channels plus exact-threshold delivery snapshots. UI tests cover5×3 cells, three independent column shortcuts, disabled columns, add/edit/remove/cancel/duplicate, mixed Bank values, names, row order, three languages/themes and chip wrapping. Full governance, independent task/final review, native Windows CI and clean Mac candidate/install evidence are recorded separately; no real phone test is sent.
