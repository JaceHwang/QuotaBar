# Bark 手机推送验收记录

日期：2026-10-23，Asia/Shanghai。开发分支 `codex/feat/bark-mobile-push`，依赖此前角色气泡与持续显示实现；本轮无公开发布或主分支合并。

## 范围与授权

用户已确认独立手机通道、原生第五设置页、安全 Key 和真实事件去重规格，并授权生成计划后多智能体并行实施。设置沿用现有苹果风格。保留现有类别开关、更新 skip/snooze、账户隔离与持续气泡行为。

## 自动化证据

代码提交：共享 Core `4dc9c33`、macOS `a3ed104`、Windows `e3d9580`。三组并行开发，root 集成，独立审查及修复复核完成。

- `./governance check all`：最终集成通过，含 Swift 全套、安装/启动清理、签名选择、Windows Core、Windows 原生/Setup/原生测试工程交叉构建，0 编译警告或错误。
- Swift Bark 聚焦：6 Core +17 AppKit/HTTP 测试通过；涵盖串行队列、双通道先后、桌面关闭、示例隔离、故障保存/清除、取消、迟到配置、重启抑制、容量及协议边界。
- Windows `dotnet run --project windows/QuotaBar.Windows.Tests/Portable --configuration Release`：假凭据/HTTP/队列/收据及配置失败回归通过；这是可跨平台逻辑测试，不替代 WPF 原生执行。
- macOS `QUOTABAR_TEST_ARTIFACTS=.dist/bark-mac-visuals`：五页×三语言×浅深色渲染和840×560边界检查通过；抽查简中浅色、繁中深色、英文深色最小窗口，文本/控件无裁切。截图版本文字由旧测试fixture固定，不是产品版本变更。
- `git diff --check`、治理快速检查通过。测试均只使用假的 Key、可注入安全存储和传输，不访问用户系统凭据或真实 Bark。

独立审查发现并关闭三项：C#缺失持久化字段误判正常、损坏文件恢复标记在立即重启后丢失、过期满容量阻止重建基线。均先新增失败测试复现，再修复复核。损坏时保留原件、持久化标记并暂停自动手机推送，显式重新开启建立当前抑制基线。

## 候选与平台边界

产品代码最终提交 `bb97083`，完整本地检查为158 Core+95 AppKit。开发 [PR #52](https://github.com/JaceHwang/QuotaBar/pull/52) 依赖未合并的 #51，保持 Draft；未合并、未发布、未安装。

- 原生CI [39824657314](https://github.com/JaceHwang/QuotaBar/actions/runs/39824657314) 与PR CI [39824670435](https://github.com/JaceHwang/QuotaBar/actions/runs/39824670435) 两端成功；该提交全部8项检查成功。
- macOS候选 `.dist/standalone-macos/candidate-20261023-014050`：来源bb97083、clean工作树、102源码指纹、程序摘要、严格签名、DMG CRC及隔离官方运行时启动/退出通过；许可证下载曾发生一次临时TLS连接失败，重试成功。替换废弃Keychain API后release构建无该警告。
- Windows当前提交原生CI包含Core、WPF UI/三语言浅深色渲染、候选完整来源校验、官方运行时启动退出、实际每用户安装/升级/回退/卸载。下载ZIP已按完整文件、PE x64、运行时摘要、来源指纹和ZIP校验和验证；初轮fd6588a候选70个Windows源码指纹与最终代码相同，最终bb97083候选另行下载核验。
- 已查看两端手机页三语言浅深色代表截图；Windows窄窗口需滚动，测试截图滚到末尾显示操作区是预期行为。截图中的旧版本文字来自既有测试fixture。Windows CI是实际Windows执行，但不替代用户自己的设备/DPI/多屏、真实凭据存取与iPhone展示验收。

## 需要用户设备确认

- 在候选设置页自行输入 Key，保存后点击手机测试，确认 iPhone 实际展示；API 接受不可替代。
- 检查 Bark/iOS 通知权限、专注模式以及锁屏展示。
- 检查真实恢复、Bank 临期或新更新事件。测试消息不算自然事件证据。
- 两端系统安全存储的首次授权/锁定状态；Windows 实际设备 DPI、多屏及长时间运行。

未执行项不得标为通过。当前日常安装和公开版本保持原状。
