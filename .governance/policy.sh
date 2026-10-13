#!/bin/sh
# Repository-specific overrides. The installer preserves this file on updates.
RELEASE_MODE=staged
RELEASE_PLATFORMS='macos-arm64 windows-x64'
FAST_CHECK_ADAPTER=.governance/project/check-fast
FULL_CHECK_ADAPTER=.governance/project/check-full
BUILD_RELEASE_ADAPTER=.governance/project/build-release
VERIFY_RELEASE_ADAPTER=.governance/project/verify-release
