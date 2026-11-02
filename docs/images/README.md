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

以上C设置实际截图已于按钮统一后刷新：Mac原生渲染及Windows产品f538e7a/CI39912163460，圆环品牌与统一蓝色操作按钮；Windows版本1.0.0仍为测试注入值。


## 2026-11-02 feature gallery

The new feature gallery is captured from product source `655a3dc9369b4d2d7880164fb4a1bcfbb3e613af` before the release version bump. These are real native control renderings with synthetic test data, not AI mockups or live account screenshots. No pixels, labels or values were edited. English and Chinese READMEs reference their corresponding language set.

- `reminders-macos-{en,zh}.png`: AppKit `NotificationSettingsTests.testMatrixRendersAllLanguagesAndThemesWithoutClippingControls`, generated locally on 2026-11-02. The example percentages and hours are editable fixture values; the disabled system/mobile columns illustrate channel-master behavior.
- `messages-windows-{en,zh}.png`: WPF `MessageCenterNativeTests.RenderVariants`, native Windows CI run [41421908044](https://github.com/JaceHwang/QuotaBar/actions/runs/41421908044), artifact `quotabar-windows-ui` ID 13129808616, 150% rendering. History selection is read while two other messages remain unread. The body text and timestamp are sample records.
- `updates-windows-{en,zh}.png`: the same Windows artifact, `update-Downloading-*` rendering. Versions 1.0.0 and 999.0.0 and the 1/2 MB download are injected test fixtures, not a public release or a measured real download.
- `display-windows-{en,zh}.png`: the same artifact, `polish-*-display` rendering with the transparency slider at an example 20%. The view is scrolled to its everyday behavior section.

Mac screenshot tests passed; Windows screenshots come from a native UI job. Screenshots describe visible behavior and do not certify device storage recovery, phone delivery or the complete platform matrix. The older 1.0.1 quota crops remain explicitly identified as historical views in each README.
