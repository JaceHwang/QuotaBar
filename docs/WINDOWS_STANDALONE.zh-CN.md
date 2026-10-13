# QuotaBar Windows 独立版候选

当前为开发候选，初始候选已通过Windows原生CI，用户于2026-10-13反馈Windows 11验收通过；最新UI优化需重新验收，尚未代码签名或公开发布。目标Windows 11 x64；自包含.NET和官方Codex 0.144.1，不需要预装CLI。功能与开发状态详见[开发进度](PROJECT_PROGRESS-standalone-app.md)。

## 安装、重开和恢复

1. 校验下载ZIP的SHA256后解压到用户目录。保持完整QuotaBar目录结构，不能只复制exe。
2. 双击 `QuotaBar/setup/QuotaBar.Setup.exe` 安装，或在PowerShell中执行 `& '.\QuotaBar\setup\QuotaBar.Setup.exe' install`。候选未签名；不要自动绕过系统安全提示。
3. 应用安装在 `%LOCALAPPDATA%\Programs\QuotaBar`，开始菜单中搜索QuotaBar即可重开。应用设置可开启登录时启动。
4. 官方浏览器登录由你完成，凭据位于 `%LOCALAPPDATA%\QuotaBar\CodexHome`；不导入桌面账户。
5. 升级仍从新解压目录执行setup。`rollback`恢复上一个包；`uninstall`删除活动入口并移入可恢复备份，账号和设置保留；`recover`恢复中断事务。运行setup时活动应用会先正常退出，必要时只终止匹配安装路径的自有应用。

卸载也可从Windows“已安装的应用”执行；安装器缓存独立于活动应用以避免锁文件。不要从活动应用目录内直接运行setup修改该目录。首次安装默认不开启登录启动，之后升级保留该状态。安装器只停用已知旧插件注册中的enabled标志、指向旧托管目录的已知启动项，以及该目录内的旧进程；保存迁移状态用于安装失败恢复，不复制旧账号数据。未知旧配置不会被猜测改写；若没有明确enabled字段，安装会安全停止并提示处理。成功安装或卸载不会自动重新启用旧插件。

## 显示与交互

托盘始终只显示透明彩色图标（蓝色轮廓、橙色额度波形；高对比度采用系统色），系统主题变更时更新。用户选择的Windows等价方案为额度放在托盘提示和自由浮窗；设置“任务栏显示额度信息”控制提示是否包含额度，不创建任务栏宽文本条。

托盘右键：额度详情、刷新、显示悬浮按钮（勾选）、设置、退出。浮窗默认开启，保存自由拖动位置。右侧关闭按钮仅移入显示，关闭保存隐藏状态且不退出应用；右键重新开启。悬停预览详情，点击固定，再次点击收起直到鼠标移出。锁定独立保持详情，关闭浮窗也收起其锁定详情。

详情卡内部沿用历史Windows插件设计：360px宽、Segoe UI、图标/标题/版本徽标、28px百分比及4px渐变额度条、紧凑Token图表、分隔明细行与右对齐数值、头像/GitHub/设置底栏。短屏或较小高度会整体滚动，避免遮挡固定区域。独立版锁定、关闭、高度调整和Tibo入口保留。

详情含双周期额度、重置倒计时、套餐、Token用量、Bank只读明细、Credits与账号信息。数据缺失显示不可用，Token不用于推算账户额度。主题/语言跟随系统，可手选浅/深色、简中/繁中/英文。关闭设置继续常驻，退出清理自有runtime。

## 本地开发与验证

使用.NET 10 SDK。核心行为测试可在macOS/Linux运行：`dotnet run --project windows/QuotaBar.Core.Tests`。交叉编译：`dotnet build windows/QuotaBar.Windows`、`dotnet build windows/QuotaBar.Setup`。Windows候选：`python scripts/build-windows-standalone.py` 或 `scripts/build-windows-standalone.ps1`，产物在 `.dist/standalone-windows/`。

## 实机验收反馈

- 记录Windows版本/架构、候选来源、显示比例。
- 安装后开始菜单图标/名称和重开有效，正常浏览器登录后真实额度出现；关闭Codex仍继续更新。
- 浮窗移入才出现关闭按钮，文字不裁切；关闭不触发拖动或详情，托盘与刷新继续；重启仍隐藏，右键恢复原位置。
- 拖动不触发详情；点击固定/再次关闭、锁定/解锁、外部点击与来源切换正确。
- 托盘提示显示开关与浮窗状态独立；语言主题、登录启动重启保存。
- 100/125/150/200% DPI、多屏/负坐标/拔插、任务栏自动隐藏、Explorer重启、休眠唤醒、断网恢复。
- 退出后QuotaBar和它的codex子进程消失；升级、回退和卸载重装保留账号设置。

不要粘贴认证文件、原始账号响应或OAuth回调URL作为反馈。可报告错误类别和不含账号内容的 `standalone-state.txt` 状态。
