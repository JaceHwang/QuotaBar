# README screenshots

Captured on 2026-10-19 from the installed QuotaBar v1.0.1 release running on macOS. The `-zh` set uses the system-resolved simplified Chinese interface; the `-en` set uses the app’s English language option. Both READMEs reference their matching language set.

- `macos-floating-*.png`: actual desktop crop of the floating control.
- `macos-menubar-*.png`: actual desktop crop of the two-line macOS menu bar item, with quota information enabled temporarily.
- `macos-details-*.png`: actual detail panel, cropped above the account footer.
- `macos-settings-*.png`: native settings, cropped below the account status/email.
- `macos-updates-*.png`: native update settings and the completed check result.

Only rectangular cropping was applied. No values, labels or controls were synthesized, translated in the image, or replaced. Values can differ between captures because the app continued refreshing. The English detail panel retains existing text truncation and its Token-data availability message. These screenshots do not certify Windows UI or an additional platform validation matrix.

The original system-language preference and menu bar icon-only setting were restored after capture. Raw captures containing account information remain outside the repository and are not documentation assets.

`character-bubble-c-reference.png` 是用户提供并选定的C角色对白视觉参考，仅用于开发验收，不作为运行时资源。

- `settings-c-connection-guide-reference.png`：用户选定的 C 设置页视觉概念，仅用于设计及验收，不作为运行时背景或真实应用截图。

- `settings-c-macos-mobile.png` / `settings-c-macos-about.png`：C设置方案实际AppKit渲染（简中浅色），示例/未配置状态；不包含真实Key或账户数据。

- `settings-c-windows-*.png`：产品提交8ac7ce1在Windows原生CI39896122629的WPF实际渲染，英文深色192 DPI与840×560滚动后的教程/关于页。版本1.0.0为测试注入值，非发布版本；无真实Key。
