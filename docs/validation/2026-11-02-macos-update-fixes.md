# macOS update fixes saved on 2026-11-02

- `adf6f3d`: Stream download progress explicitly; cancel the initial AppKit termination request, finish asynchronous cleanup, then terminate. Includes the initial 10-second check delay.
- `36e8d4f`: Preserve safe update failure domain/code and last reported phase; remove the generic installation-path suggestion.
- This checkpoint aligns the earliest permitted automatic check with the 10-second startup delay, with clock-boundary coverage and automatic-check opt-out coverage.

Verification: six QuotaUpdateViewTests passed on 2026-11-02. The previously installed diagnostic candidate completed a real update to official 1.5.0: ready/handoff at 2026-10-31 10:44:53 Asia/Shanghai, health at 10:44:56 and succeeded at 10:44:58. The latest scheduling correction has not been packaged or installed. Official 1.5.0 release assets remain unchanged and do not include these fixes.

Windows message-storage diagnostics and its pending scheduler correction remain outside this checkpoint. No push or public release is performed for this save request.
