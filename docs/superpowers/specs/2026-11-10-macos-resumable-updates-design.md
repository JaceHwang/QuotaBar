# macOS resumable updates

Goal: provide the download resumption and verified package reuse implemented by Windows commit f808161 on macOS, including after an installation failure. Preserve existing UI, update trust rules, and fresh per-attempt installation jobs.

Approaches: URLSession resume data is tied to opaque session state and server validators; a content-addressed cache with explicit HTTP Range follows the established Windows behavior and can verify every byte against fresh release metadata. Use the latter. Keep cached assets outside UUID job directories, reserve the cache across processes, and import only independently verified assets from old job directories.

For each attempt resolve release/tag metadata again, reject unsafe paths and redirects, validate Range and length, and recheck SHA-256 and provenance before staging fresh copies. Preserve partial data on cancellation or transport failure, discard invalid complete data, and prevent concurrent cache writes. Respect existing package validation and handoff. Do not change version, UI, release, or installation state.

Verify with failure-first tests for Range responses, interruptions, cache reuse, corruption, legacy jobs, and concurrent use; run the macOS and Windows Core checks. Distinguish CI, device, and release evidence.
