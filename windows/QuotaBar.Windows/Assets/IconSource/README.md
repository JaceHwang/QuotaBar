# Windows circular application icon

Input: user-provided circular quota badge screenshot, 2026-10-13.
Built-in imagegen reconstructed the navy/coral motif at high resolution. Original generated source: quota-circle-source.png. This file is retained to make packaging reproducible.

Prompt: Faithfully upscale the circular white badge containing the navy quota ring, two small navy dots (right dot slightly higher), and coral wave; remove the gray rectangle; preserve proportions, palette and orientation; transparent outside; no redesign, text or extra objects. Refine the circular edge and remove stray external flecks.

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/build-windows-icon.swift windows/QuotaBar.Windows/Assets/IconSource/quota-circle-source.png windows/QuotaBar.Windows/Assets`

The native asset compiler constrains the raster motif inside an exact circle, excludes reconstruction edge flecks, and emits the 1024px PNG plus ICO frames at 16/20/24/32/40/48/64/128/256px. Use the same ICO for every Windows theme and the app/setup executable. The white interior is intentional; only the exterior is transparent.

X button mark: monochrome vector form based on the [official X brand guide](https://about.x.com/content/dam/about-twitter/x/brand-toolkit/x-brand-guidelines.pdf). It identifies the existing Tibo account link; it does not imply endorsement.
