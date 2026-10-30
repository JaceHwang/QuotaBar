# Notification master switches implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this small change in the current session.

**Goal:** Use channel switches to enable matrix columns and move channel testing directly below the matrix.

**Architecture:** Reuse the approved A matrix and existing native switch components. Preserve category selections while disabling closed channel columns. Example test events use master channels, independent of category rules, with explicit mobile test delivery.

**Tech Stack:** AppKit/Swift, WPF/C#.

**Spec:** User request and explicit approval on 2026-10-25: 直接沿用 A，跳过效果图并实施。

## Global constraints

- Skip new mockups at user request; preserve A layout, theme, typography and compact density.
- Native keyboard/focus and accessible names; disabled matrix cells cannot mutate policy.
- Keep selections when master closes; do not change versions or publish.
- Test notification uses sample data, no real quota/history mutation. No automatic real phone test during development.

## Review focus

- Disabled column click cannot alter saved rules; reenable restores selections.
- All masters off prevents every test channel; category rules do not block a channel test.
- Mobile test must use its dedicated test API, since production mobile ignores test events.
- System permission failure must not prevent bubble/mobile test.
- Three languages and light/dark preserve visible controls and switch names.

## Tasks

- [x] Add failing macOS matrix tests for switches, disabled cells and test position; add test routing regression with legacy mode disagreeing with policy.
- [x] Replace macOS master checkboxes with QuotaSettingsSwitch; disable corresponding cells on refresh and guard handlers. Apply equivalent WPF behavior.
- [x] Pass test action into the matrix, remove old bottom button in policy mode, route sample tests by masters and explicit mobile test API.
- [x] Run focused native tests and rendered UI checks; cross-build Windows and run appropriate governance checks. Record unrun Windows device tests separately.

## Execution evidence

Mac red tests reproduced missing switches and legacy routing, then passed after implementation. A second controller regression reproduced celebration preview sending mobile tests; previews now remain local on both platforms. Dedicated Bark tests use an injected fake transport. Independent static review found no P1/P2. Native Windows device/CI evidence must be recorded separately from macOS cross-builds.
