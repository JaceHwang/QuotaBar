# Unified Message List Implementation Plan

> Execute in this session using regression tests before product changes.

**Goal:** Show all messages in one chronological list, emphasize unread cards, and restore default styling after a successful read.
**Architecture:** Both native message-center views consume the existing durable history and preserve its read semantics; the row renderer derives typography and surface from the record state, with selection/focus separate. Retain responsive detail navigation and storage failure recovery.
**Tech Stack:** Swift/AppKit, C#/WPF, existing message-center store and fixtures.
**Spec:** docs/superpowers/specs/2026-11-04-unified-message-list-design.md

## Global constraints

- Preserve actual messages and read persistence; opening a row must not read another row.
- Keep chronological order, all-read action, keyboard access, light/dark appearance and narrow-window detail navigation.
- UI presentation follows the user-selected C reference; no public release without authorization.
- macOS and Windows implementations must both be covered; Windows native device results must not be inferred from cross-compilation.

## Review focus

- Read persistence failure leaves the item visibly unread; test storage error and retry.
- Selection restoration and newly arriving messages do not mark another record read.
- Read/unread styling updates correctly in reusable/virtualized rows and both themes.
- Selected, focused and unread states remain distinguishable with keyboard use.
- An empty list, long strings, narrow windows and 10,000 records remain usable.

## Tasks

- [ ] Complete native tests for unified rows, state styling and successful/failed read transitions. macOS red/green verified; Windows UI tests are authored and cross-compiled but not yet run on Windows.
- [x] Implement macOS and Windows unified list and C row styling without changing storage contracts.
- [x] Update active documentation and verify macOS native appearance, accessibility, cross-platform builds and applicable local suites. Windows native appearance and interaction remain unverified.
- [x] Package and install macOS candidate when validated; record Windows CI/device limits and update project board.
