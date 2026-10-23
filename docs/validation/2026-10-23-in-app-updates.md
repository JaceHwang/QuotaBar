# 应用内更新验收（开发候选）

## 范围

用户批准规格与五任务计划，并选择当前会话原生执行。开发分支 `codex/feat/in-app-updates`，基线 `f936533`；产品版本维持1.3.0。未授权此功能公开发布，未替换本机已安装应用。

## 本地证据

- `7b23045`：Swift/C#共用24组正式release/tag/来源/摘要/size/URL拒绝样例。
- `31ade76`：下载与暂存，完整治理通过；HTTP长度/重定向、晚到取消、摘要/来源、ZIP路径/链接/大小写冲突、磁盘拒绝。
- `22314de`：Mac原生助手、Windows setup update、私有job与ready/health/result回执；真实Mac进程验证安装、立即退出回退、损坏/过期拒绝及重放。Windows此阶段只有Core/交叉构建，未记为原生完成。
- `64baae7`：关于页真实按钮、取消/重试/说明链接、气泡明确更新入口、系统通知打开关于页；晚到进度不会重新启用取消，双击不并发。Mac三语言×两主题×下载/校验/准备/失败渲染24张，840×560可滚动。
- 任务5新增：实际只读签名DMG的挂载/校验/复制/卸载；父进程退出超时不替换；真实助手恢复中断日志；两次helper就绪互斥；新进程健康回执早于凭据读取，最终结果稍后读取一次；运行中目标版本固定；Windows从已校验ZIP重新核对暂存，伪造自洽清单被拒绝；旧包缺少更新协议被拒绝。

测试夹具不使用真实账户、Key或远程安装目标。Mac助手夹具在隔离HOME内编译并本地签名；fixture应用健康回执后继续存活，用来模拟正常常驻/授权等待，不将其当作真实账户验收。

- 最终取消边界：真实助手“就绪后父进程退出但没有handoff许可”先复现错误安装（RED），双端加入独立交接许可；Mac七场景全部通过。许可只能在当前操作代次/互斥状态内消费，普通退出或已取消代次不能授权安装。

## 原生CI与候选

e25cd9b的原生CI39970006140、39970014258双端全部通过；治理39970014020、39970006220通过。Mac候选candidate-20261023-223042完成来源、签名、隔离启动与DMG校验。最终复核修复后的准确HEAD与新原生CI仍待记录。不能以Windows交叉构建代替原生安装与UI；不能把测试夹具成功当作真实官方跨版本更新已发生。

## 设备与发布

本轮未对用户当前安装执行升级，未发送真实Bark推送。自然真实更新、不同磁盘/网络、Windows用户设备、系统授权体验和长期运行仍需候选验收。旧v1.3.0需一次手动安装包含助手的新版本。公开发布需要后续明确授权，版本由Release Please生成并从准确tag构建。


## 最终复核修复

- 回执写入失败：Mac真实助手先复现误报回退；安装提交后仅尽力保存成功回执，不再重启/终止健康新版。Swift/C#事务暴露待恢复日志状态，恢复失败保留日志与备份，不声称已回退。
- 中断恢复：真实新版和运行时仍活着的夹具先复现残留进程；恢复助手仅按固定安装目录的精确可执行路径识别并停止两者，再恢复旧包。
- Windows退出：Core延迟清理夹具先因缺少等待API失败；追踪活动任务并在Coordinator.Quit关闭应用前等待。新增独立原生UI进程覆盖runtime尚未创建时的实际Quit。
- 本地Mac真实助手八场景全部通过，Windows Core与UI交叉编译通过；新增Windows原生用例等待CI。
- 次要项暂缓：结构化Failure字段尚未展示，失败仍显示通用三语言提示。

- 原生CI40003237532中，回执失败/取消/成功更新均通过，随后卸载遇到进程退出竞争（Win32 299，MainModule读取失败）。新增回归要求仅在有界确认进程已退出后忽略299，未确认的活进程身份错误继续拒绝操作，不跳过安装器测试。新提交需重跑原生CI。


## 最终候选与原生证据（2026-10-24）

- 产品52c6ae8：原生CI [40003242174](https://github.com/JaceHwang/QuotaBar/actions/runs/40003242174)双端成功，治理40003242223、40003237507成功。Windows实际Quit、24状态/语言/主题截图、完整候选、启动退出、安装/回退/卸载、更新助手六场景通过。另一次并行运行40003237532暴露上述299退出竞争，加固不因成功重跑而省略。
- Mac最终候选`candidate-20261024-022754`：来源commit52c6ae8，119项来源指纹与签名后程序/运行时/助手摘要一致，严格签名、实际隔离启动退出、DMG CRC/SHA256通过；候选内真实助手八场景再次通过。第一次构建因GitHub许可证下载TLS中断失败，完整重试后通过，未跳过校验。
- 进程竞争加固：Core失败回归→通过，活进程身份不明仍拒绝；完整治理再次通过。该加固的最新原生运行与最终交付状态见[Draft PR57](https://github.com/JaceHwang/QuotaBar/pull/57)及项目看板，不将历史CI当作新代码证据。
- 本轮没有执行用户真实安装、合并或公开发布；旧v1.3.0仍需一次手动安装包含更新助手的版本。

## 实施取舍和验证边界

- Ruling: use contracts/in-app-updates rather than test-fixtures — existing .NET project copies contracts automatically and other shared fixtures live there; no semantic scope change.
- Ruling: tag-cases folded into release-cases fixture rows so both parsers always see tag and asset together.
- Ruling: shared download/package validation belongs in QuotaCore/QuotaBar.Core so GUI and helper reuse it; UI generation/start/cancel orchestration stays Task4 — no loss of validation; interface drift would require paired tests.
- Ruling: incoming Mac packages require updateProtocol1 and updaterSignedSha256, added by Task3 packaging — prevents installing a package without an updater; old versions require manual fallback.
- Ruling: URLs are compared by normalized path for filesystem identity; Foundation adds directory URL trailing slashes — rejecting that form broke a real temp-filesystem transaction test. Symlink resolution must still match path exactly.
- Ruling: real-helper E2E scripts were introduced with Task3, ahead of Task5 wiring, to verify the helper before UI consumes it — avoids deferring process-boundary evidence; Windows results remain pending native CI.
- Ruling: system notification/unread-list clicks open About; only the explicitly labelled bubble/button starts download — prevents old notification clicks silently initiating installation.
- Ruling: source is frozen at e25cd9b and local full checks pass, so the one read-only whole-branch review overlaps external native CI during Task5 verification — this avoids idle time without adding implementation agents; any CI/review code changes still require RED→GREEN and full checks before completion, with the risk of later findings covered by that fix pass.
- Final: minor (deferred): structured ApplicationUpdateProgress.Failure is not surfaced; generic localized failure text remains.
- Final: Ruling: compromised repository/current-user account is outside this updater trust boundary — official HTTPS release metadata and the current installation remain trusted — compromise can replace trusted binaries and requires a separate signing/security project.
- Final: Ruling: real user device, Bark permissions and a natural published cross-version update are not certified by fixture/native CI — retain explicit device-validation limits — platform-specific device issues may remain.
- Final: Ruling: reviewer did not independently certify CI — primary queried e25cd9b native CI39970006140/39970014258 and governance39970014020/39970006220, all succeeded — new fixes still require new-head native CI.
