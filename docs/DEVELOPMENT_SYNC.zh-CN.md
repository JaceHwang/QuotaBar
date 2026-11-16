# Windows 与 macOS 双实机开发

GitHub 保存共享代码和验证记录。两台实机分别构建、安装和验收同一个源码提交，版本发布从两端验证后的集成提交生成。

## 顺序交接

一个功能使用一个 `codex/<type>/<slug>` 分支和一个草稿 PR。提交前执行快速检查，普通推送自动执行快速检查及本机平台测试。Windows 使用 Git Bash、Python 和 .NET 10，macOS 使用 Xcode、Python 3 和 .NET 10。

```sh
./governance bootstrap
./governance check local
git push -u origin "$(git branch --show-current)"
```

Windows 本地检查运行完整 Core 测试、应用和安装器构建、原生 Windows UI 测试。macOS 本地检查使用原有完整检查，包括 Swift、安装夹具、签名和 .NET 验证。GitHub 对开发分支推送及所有 PR 执行两端 CI。

需要把未完成的代码交给另一台实机时，可以显式使用草稿同步模式。它仍执行全部快速检查和本机测试，并在本机测试失败时输出失败状态，允许功能分支继续同步。

```sh
QUOTABAR_DRAFT_SYNC=1 git push -u origin "$(git branch --show-current)"
```

该模式仅允许 `codex/<type>/<slug>` 功能分支，PR 必须保留草稿状态并记录具体失败。快速检查失败会阻止同步，CI、主分支、预发布分支和标签均拒绝使用草稿同步模式。CI 的完整检查不读取此例外开关。

另一台实机首次接续当前修复时执行以下命令。

```sh
git fetch origin
git switch --track origin/codex/fix/beta-channel-save
./governance bootstrap
./governance check local
```

分支已经存在时执行 `git switch codex/fix/beta-channel-save` 和 `git pull --ff-only`。遇到分叉时先保留两端提交，再协调合并或变基。

## 同时开发

两台机器同时工作时，各自使用功能分支，例如 `codex/fix/beta-channel-save-windows` 和 `codex/fix/beta-channel-save-macos`，通过 PR 汇入共同功能分支。按功能集成，避免维护长期分叉的操作系统版本线。

## 验收和发布

PR 记录每端的源码 SHA、候选包 SHA-256、系统及测试结果。源码发生变更时，评估并补做受影响的平台验证。构建来源和实机结果分开记录。

主分支和预发布分支的远程保护要求以下检查通过。

- `macOS build and verification`
- `Windows standalone build and verification`
- `governance / policy`

`./governance check all` 保留原有完整跨平台检查，由 macOS 实机或 CI 执行。草稿同步允许先共享代码，双平台 CI 和实机验收决定后续合并与发布。

发布继续通过 Release Please 管理版本。平台发布工作流在精确标签检出后核验同一源码提交的最新 CI 运行，并确认其中 macOS、Windows 两个作业均成功。缺少、失败、运行中或不同提交的证据都会阻止发布。
