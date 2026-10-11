# macOS standalone candidate validation

日期：2026-10-11（Asia/Shanghai）。环境：macOS 27.0（26A428），arm64，Xcode 27。范围：本地开发候选；不是公开发布或公证证明。

## 当前候选

`candidate-20261011-133422`，bundle id `com.jace.codex-quota`，现有版本号保持 0.4.0；内嵌官方 `codex-cli 0.144.1`。用户 Applications 中已安装并运行，官方重新登录后取得真实额度和账户。来源快照逐文件比对无差异，严格签名与 DMG 校验通过。候选为未提交源码构建，外部 provenance 记录签名后二进制摘要。

## 已通过

| 项目 | 现场证据 |
| --- | --- |
| 官方登录与查询 | 用户完成官方身份验证；新回调端口确认监听，状态 `ready has_quota=true`，账户和实际额度可读 |
| UI 与详情 | 设置实际显示账户及更新时间；原卡片 AX 内容包含主/副额度、套餐、重置、Bank/Credits/Token 和账户；`detail_visible=true detail_fits_screen=true` |
| 主题/语言 | 实际深色设置截图检查；英文、繁中切换，最后恢复系统主题/语言 |
| 后台刷新 | 更新时间 13:31:35 → 13:32:39 → 13:33:45 持续推进，约 60 秒周期 |
| 单实例 | 再次直接启动 bundle executable 返回 0，父应用进程仍仅一个 |
| 关闭/退出 | 关闭设置后仍常驻；Cmd-Q 无 app/runtime 残留；修复后 SIGTERM 0.63 秒退出且子进程清理 |
| 运行时崩溃 | 仅终止应用直接拥有的 runtime，观察 `ready → offline → ready`，2.63 秒恢复 |
| 登录启动 | ServiceManagement 实测状态启用 `1` → 禁用 `0`，最终保持关闭 |
| 安装事务 | 升级、双向 rollback、uninstall/reinstall 均成功，恢复后真实额度可读，账户保留 |
| 旧模式迁移 | 默认停用旧 plugin flag 与 LaunchAgent；确认无旧进程。restore-legacy 实际恢复旧服务成功，随后再次迁回独立版 |
| 来源 | SOURCE-SNAPSHOT 中全部文件与当前源码哈希一致；许可和内嵌运行时来源记录存在；安装后的 app/runtime/快照/provenance 与候选逐字节摘要一致 |
| 自包含载荷 | app 与 runtime 的 27/14 项链接依赖全部来自系统库，DMG SHA256SUMS 复核通过；宿主退出持续刷新已由用户实机确认 |
| 测试 | 最新 Swift 343 项（Core 251、Installer 51、AppKit 41）；安装器 Python 7 项；完整 governance check all 成功 |
| 资源抽样 | 一次空闲样本 app/runtime CPU 0.0%/0.4%，RSS 144784/86272 KiB，仅一个采集子进程；非长期基准 |

## 仍待确认

- 新候选菜单栏两行额度及重置日期完整显示：用户实机确认通过；工具仅能截取设置窗口。
- 真实休眠/唤醒、实际断网/代理、多显示器/菜单栏拥挤、macOS 14 干净设备和长期稳定性仍待发布矩阵验证。状态退避与协议错误已有自动回归，不能代替这些硬件场景。
- 首次真实认证过期与官方重新登录已观察；取消/登出主要由协议回归覆盖，未宣称全部账号切换组合实机通过。
- Developer ID 公证未执行：本机只有 Local Signing 身份。本地候选可安装测试；正式公开分发需要额外签名与公证验收。
- Windows 和公开发布不在本轮授权范围。

## 失败与修复记录

旧候选登录回调曾拒绝连接，未计为通过；重装修复候选并重新登录后恢复。早期 SIGTERM 停机和后台 timer 未通过；改为 async-signal-safe self-pipe、主 RunLoop common timer 直接执行后，退出和连续刷新实测通过。安装器初版迁移非事务/默认共存问题已通过恢复日志、精确停用和故障注入修复。最终只读复审未发现阻止当前本地候选验收的问题。

## 可重复命令

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path plugins/codex-usage-sidebar/native
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-macos-standalone-install.py
bash plugins/codex-usage-sidebar/tests/test-sidebar-control.sh
bash scripts/build-macos-standalone.sh
git diff --check
./governance check all
```

设置截图只保存在忽略的本机 `.dist` 中，不把个人账户信息提交到文档或公开仓库。

### 宿主缺席最终确认

2026-10-11 用户实机确认：关闭 Codex 时独立应用仍正常显示并持续刷新。此项证据来自用户观察，解除此前待确认项；不代表 Windows 或公开发布验收。新增菜单栏额度和日期显示已重新构建并安装 candidate-20261011-173154。Swift 343 项、安装器 7 项及治理检查通过；应用严格签名、DMG 摘要通过，安装后真实额度 ready。用户随后实机确认“两行均完整显示”，此项通过。

### 菜单栏垂直居中修复候选

candidate-20261011-173815：按实际文字尺寸绘制模板图像并使用系统按钮居中图像布局。完整 Swift 343 项与治理检查通过，打包校验、安装严格签名及来源快照一致性通过，真实额度 ready。用户此前确认文字完整显示，随后反馈垂直不居中；用户随后实机确认“已居中”，本修复的垂直居中验收通过。
