#!/usr/bin/env bash
set -euo pipefail

NAJEEB_IOS_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NAJEEB_SCHEME="${1:-Najeeb}"
NAJEEB_BUILD_ROOT="${NAJEEB_BUILD_ROOT:-${NAJEEB_IOS_ROOT}/.build/xcode/${NAJEEB_SCHEME}}"

xcodebuild -project "${NAJEEB_IOS_ROOT}/Najeeb.xcodeproj" \
    -scheme "${NAJEEB_SCHEME}" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${NAJEEB_BUILD_ROOT}" \
    CODE_SIGNING_ALLOWED=NO build
