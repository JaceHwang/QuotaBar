# Resumable Windows update downloads

Implement the user's request on the existing Windows updater branch lineage.

Persist content-addressed asset files in Updates/downloads, separately from per-attempt GUID installation directories. Re-resolve trusted release metadata on every attempt. Serialize cache access with a file lock. Preserve partial data on interruption/cancellation and verified assets after installation failure. Each installation gets fresh job credentials and receipts. Import valid archives/provenance from legacy GUID caches so existing failed updates can be reused.

HTTP requests resume with Range and accept append only for an exact matching Content-Range and total size. A full 200 response restarts the file. Reject malformed ranges and unsafe redirects. Final length, SHA-256 and source identity checks remain mandatory. Invalid complete data is removed for a fresh retry.

1. Add failing range/restart/interruption tests, then implement transport behavior.
2. Add failing cache reuse, legacy import, corruption and concurrency tests, then implement shared asset cache and retain normal task cleanup.
3. Run Core/native Windows checks and independent review. Probe real GitHub Range support and legacy reuse using the application's download entry point. Install a verified local candidate with the new Core DLLs after backing up the active installation.

Cancellation pauses download data for reuse. The scope is Windows, with public transport signatures preserved. Mac behavior is separately tracked.
