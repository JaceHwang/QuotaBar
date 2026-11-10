# macOS Resumable Updates Implementation Plan

**Goal:** Match Windows update resumption and verified asset reuse on macOS.

**Architecture:** Keep digest-keyed cached assets separate from per-attempt jobs. Resolve fresh release metadata, serialize access, verify and copy assets into a fresh job, and use explicit HTTP Range with strict response validation.

**Tech Stack:** Swift 6, Foundation URLSession, CryptoKit, XCTest.

**Spec:** docs/superpowers/specs/2026-11-10-macos-resumable-updates-design.md

## Tasks

- [x] Add failing HTTP and client tests for resume, interruption, cached retries and invalid responses.
- [x] Implement Range streaming, content-addressed cache, verified legacy import and exclusive access; preserve existing trust checks.
- [x] Run focused tests and complete local governance checks; record CI/device limits and update progress.
