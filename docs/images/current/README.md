# Current native UI renders

Generated 2026-09-15 from the AppKit views published for macOS v0.4.0.
These are deterministic native-control renders, not live Codex screenshots, not AI-generated
mockups, and not proof of a published release. Quota/Bank/Token data and `demo@example.com` are
fixtures. Card images show detail-lock enabled. Original data dates are fixed for repeatability.
Long English labels reflect the current fixed-width rendering, including clipping; images are not
retouched to imply a different product layout.

- `detail-{en,zh-cn}-{light,dark}.png`: current quota card with lock, settings and urgency colors.
- `position-{en,zh-cn}-light.png`: current right-click position selector.
- `settings-{en,zh-cn}-light.png`: current four-action footer menu.

Reproduce from the repository root (the suite also exports Traditional Chinese/dark menu variants):

```bash
CUS_VISUAL_OUTPUT_DIR=/tmp/sidebar-doc-visuals CUS_VISUAL_VERSION=0.4.0 \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  SDKROOT="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx --show-sdk-path)" \
  xcrun swift test --package-path plugins/codex-usage-sidebar/native \
  --filter QuotaDetailCardVisualTests
```

The renderer's `tibo-<locale>-<theme>.png` is the legacy fixture output basename; rename it to
`detail-<locale>-<theme>.png` when copying reviewed images here. This does not represent a Tibo UI
feature. Existing older images remain available for historical version documents; current README
references point here. The production app and installed companion are not replaced by this render.

## 实机截图

`live-macos-indicator.jpg`：2026-09-16，从已安装的 Codex Usage Sidebar 0.4.0 本地构建窗口直接截图。实际实时额度，仅截图伴生窗口，不包含宿主应用对话或账号标识。其余 PNG 为固定数据原生控件渲染图。
