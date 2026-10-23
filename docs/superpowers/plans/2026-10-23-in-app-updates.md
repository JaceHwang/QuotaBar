# QuotaBar In-App Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 用户点击一次后下载、校验、安装并重启，保留配置，失败回退，覆盖macOS与Windows。

**Architecture:** 保留Pages版本发现，用固定GitHub API解析确切正式release及tag，双端Core校验同批fixtures。平台服务负责受控流式下载与私有暂存；受信任本地独立助手执行原子安装和启动回执，UI仅呈现状态与用户操作。

**Tech Stack:** Swift/AppKit/Foundation/CryptoKit、C#/.NET10/WPF、现有TransactionInstaller和GitHub Actions；无额外服务器、用户token或Python运行依赖。

**Spec:** `docs/superpowers/specs/2026-10-23-in-app-updates-design.md`，该规格所有契约均为验收条件。

## Global Constraints

- 原生双端、简中/繁中/英文；现有蓝色30pt/13pt半粗体/7pt圆角按钮。
- 用户点击才开始下载；不会后台自动安装，不重复回放。
- 固定JaceHwang/QuotaBar正式release、精确文件名、可信size/SHA256、来源commit/tag/平台一致；失败不得降级为免校验安装。
- 元数据2MiB、来源1MiB、下载512MiB、解压2GiB/20000项、重定向10次；仅HTTPS显式域名；仅标准每用户目录。
- 原配置、凭据、启动项与旧版备份保持；助手不提权，不依赖系统Python，不绕过系统签名/授权。
- 每任务先失败回归→最小实现→聚焦验证→提交；完整治理/原生CI完成后才称开发完成。产品版本仍由Release Please管理；本轮不公开发布。

## Review Focus

1. 取消或旧响应到达后不能发起安装（任务2/4的取消代次测试）。
2. 合法外层ZIP内重复/链接/大小写路径不能覆盖（任务2的恶意归档测试）。
3. feed被篡改仍不能下载/执行其他仓库或预发布资产（任务1的固定来源测试）。
4. 现有Bark Key导致系统授权等待不能误判启动失败并回滚（任务3/5启动回执边界测试）。
5. 助手/主进程崩溃后不能丢失旧安装或重放更新（任务3/5日志恢复与重复nonce测试）。

### Task 1: 官方发布与操作状态契约

**Files:** Create `native/Sources/QuotaCore/TrustedUpdateRelease.swift`, `windows/QuotaBar.Core/TrustedUpdateRelease.cs`, `test-fixtures/in-app-updates/release-cases.json`, `test-fixtures/in-app-updates/tag-cases.json`; tests `native/Tests/QuotaCoreTests/TrustedUpdateReleaseTests.swift`, `windows/QuotaBar.Core.Tests/TrustedUpdateReleaseTests.cs` and existing test runner registration.

**Interfaces:** `TrustedUpdateRelease.parse(releaseJSON, tagJSON, version, platform, currentVersion)` → exact asset(name,url,size,sha256), provenanceAsset, sourceCommit; `ApplicationUpdatePhase` and `ApplicationUpdateProgress` define same JSON names/phase meanings in both languages. Existing UpdateRelease/feed remains compatible.

- [x] Write shared fixture tests accepting stable2.0.0/current1.3.0 and rejecting each source/size/digest/tag/version violation listed in spec, including duplicate names and fake URL userinfo/port.
- [x] Run Swift Core/.NET Core tests, observe failures for missing contract.
- [x] Implement parser with exact bounds and existing semantic-version comparators; pin API/tag/CDN URL policies as shared tested data.
- [x] Run both real parsers against all fixtures; reject drift and commit.

### Task 2: 受控下载、暂存与校验

**Files:** Create `native/Sources/CodexQuota/ApplicationUpdateService.swift`, `ApplicationUpdatePackage.swift`, `windows/QuotaBar.Windows/ApplicationUpdateService.cs`, `windows/QuotaBar.Core/UpdateStaging.cs`; tests in corresponding native/Core projects.

**Interfaces:** service `start(release)`, `cancel()`, read-only `progress`, change callback; resolves task1 assets, streams package/provenance, produces `PreparedUpdate` only after verification; installer remains injectable at interface boundary for tests, never test-mode shortcuts in production.

- [x] Add failures for corrupt/truncated/over-limit stream, untrusted redirect, cancellation after finalbyte, double click, insufficient disk, mismatched provenance/source, malformed/duplicate/path-traversal/symlink ZIP.
- [x] Observe tests fail before implementation.
- [x] Implement ephemeral no-cookie/no-auth transport, strict redirects/length/SHA256, per-operation generation and private UUID staging. Validate package version/platform/tag/commit and existing full manifests; Mac safely mount/copy/unmount DMG.
- [x] Assert old app remains running on all pre-handoff failures; cleanup only owned nonactive paths. Run focused tests and commit.

### Task 3: 两端独立助手及事务恢复

**Files:** Create `native/Sources/QuotaBarUpdater/main.swift`, `native/Sources/QuotaCore/ApplicationUpdateTransaction.swift`, `windows/QuotaBar.Core/ApplicationUpdateTransaction.cs`; modify `native/Package.swift`, `native/Sources/CodexQuota/main.swift`, `windows/QuotaBar.Setup/Program.cs`, `windows/QuotaBar.Windows/Program.cs`, packaging/source verifiers. Add transaction/real-helper tests.

**Interfaces:** schema1 `UpdateInstallJob` holds operationID, targetVersion, sourceCommit, expected digests, fixed-root relative staged paths, expectedParentPID, nonce, expiresAt; atomic `ready`/`health`/`result` receipts; helper accepts only a job in its own validated staging root. Windows `setup update` reuses TransactionInstaller; Mac native transaction matches old installer preservation semantics.

- [x] Add failures for wrong target, tampered staged payload, expired/replayed task, helper notready, parent identity/timeout, competing lock, rename failure, missing health/immediate exit, and interrupted journal recovery.
- [x] Run Core/native tests and observe failures; use real temporary filesystem faults where possible.
- [x] Implement helper handshake (ready within10seconds before app quits),10-minute task expiry,20-second parent wait, same-volume backup/atomic switch and registration preservation. Launch new app with nonce health within15seconds and then2seconds survival, return rollback receipt and re-open old on failure. Health precedes credential UI; no network dependency.
- [x] Package/sign Mac helper; include all helper files/digests in source/provenance verification. Windows copy trusted CURRENT setup directory outside target before exit. No downloaded setup executed before validation.
- [x] Run real helper happy/failure processes in temp contexts and ensure no leaked process/mount, then commit.

### Task 4: 关于页和提醒入口接线

**Files:** Modify `native/Sources/CodexQuota/QuotaUpdateController.swift`, `StandaloneCoordinator.swift`, `CharacterNotificationBubble.swift`, `windows/QuotaBar.Windows/UpdateController.cs`, `Coordinator.cs`, `SettingsWindow.cs`, `CharacterNotificationBubble.cs`; extend existing update/render tests.

**Interfaces:** “Update now/立即更新/立即更新” starts pinned Available snapshot; “Cancel/取消/取消” cancels before handoff; old `openRelease/Open` kept for “View release notes/查看更新内容/查看更新內容”. Notification clicks open update section; explicitly labelled bubble action downloads. Callback routing preserves delivery tokens and context validity.

- [x] Add real-control failures for explicit-click-only start, progress transitions, repeated clicks, cancel/late response, network/verification failure with retry/manual link, action labels, and legacy skip/snooze policy.
- [x] Observe failure, wire service and helper, preserve auto-check frequency/reminder settings. Disable cancelling only after ready/handoff; stop only self-owned runtime on graceful exit.
- [x] Render all phases in three languages/two themes/840×560; assert labels fit and last controls reachable; keep keyboard/focus/readscreen state. Commit after focused tests pass.

### Task 5: 原生端到端、打包与交付

**Files:** Create `scripts/test-macos-in-app-update.py`, `scripts/test-windows-in-app-update.py`; modify `.github/workflows/ci.yml`, build/verify scripts and relevant installer tests; update README, privacy, troubleshooting, update operations, roadmap and validation record.

- [ ] Build isolated old/new test bundles from current product without editing tracked product versions. Exercise actual helper replacement/restart, config preservation, corrupt package refusal, immediate-exit rollback, timeout and interrupted transaction recovery.
- [ ] Wire Windows runner native test and require real process results; crossbuild alone does not pass Windows acceptance. Mac native process test includes keychain-wait-compatible basic health.
- [ ] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path native`, `PATH="$HOME/.local/share/quotabar-dotnet:$PATH" dotnet run --project windows/QuotaBar.Core.Tests/QuotaBar.Core.Tests.csproj`, Windows WPF native runner and `./governance check all`; inspect every result.
- [ ] Run exact-source candidate packaging/source and startup checks. Confirm updater resource is bundled, old releasefeed tests pass, no API secrets/files leak, runtime exits cleanly. Native platform CI must pass before claiming complete.
- [ ] Update docs with bootstrap installation limitation, free/public API dependency, signature-system prompt limits and manual fallback; record implemented/local/CI/device/published separately. Create Draft PR, attach it, and keep public release for later explicit authorization.

## Execution and review

Recommended: native execution in the current session, because service/state/helper interfaces are coupled and one implementer can keep the trust boundary consistent; one independent whole-branch review at the end. Alternatively choose subagent-driven task/review execution. User reviewed and approved native execution on2026-10-23; product implementation now in progress.
