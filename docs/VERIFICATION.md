# Verification

The folder consolidation was verified on 12 October 2026 with Xcode 27 and Swift 6. The app and its saved-game behavior were kept intact; no hosted-agent or backend changes were made during this reorganization.

## Automated checks

- Before reorganization: 53 game/voice tests and 34 API tests passed in the two original packages.
- After reorganization: all **87 tests** pass together through the root `Package.swift` and `NajeebLogic` test module.
- **Najeeb**: full iOS Simulator build passed.
- **Najeeb-CarPlay**: full iOS Simulator build passed.
- Agent provisioning utility compiled; dry-run resolves the new configuration path and validates all twenty response-waiting client tools.
- Xcode source membership, resource paths, plist/entitlement paths and documentation links checked.
- Both builds emit only Apple's informational AppIntents metadata warning because the app does not use AppIntents.

## Repeat locally

From the repository root:

```sh
swift test
./scripts/build-native.sh
./scripts/build-native.sh Najeeb-CarPlay
```

The Xcode shared lockfile pins SDK dependencies. Package resolution may require network access on the first build. The root Swift package has no external dependencies and tests the same source files used by the Xcode app.

## Scope and limits

Game tests cover setup, eighteen-question progression, semantic-answer verdicts, scores, helpers, stale/duplicate requests, final results and legacy-state decoding. Voice-input tests cover activation variants, calls in the middle of an utterance, explicit submissions, expiration and turn isolation. API tests use mock transport for question filtering, helper validation and email/OTP/name/cookie contracts.

No fresh full spoken game or CarPlay runtime session was performed for this source-folder change. Arabic recognition, overlapping speech and actual phone/Bluetooth routes need the [manual acceptance scenarios](VOICE_TEST_MATRIX.md). A passing CarPlay build does not establish simulator functionality or entitlement approval.

## Original palette restored — 12 October 2026

Restored the earlier cream canvas, neutral cards and badges, black navigation tint and black primary buttons with white labels. The current team's white card and black border identify its turn. Removed the multicolor accent helpers and gradient background; fonts, layout and gameplay are retained.

The iPhone simulator build passed with the existing AppIntents metadata notice. Game/API/voice logic was not changed, so the 87-test suites were not rerun for this visual edit.

A fresh, isolated iPhone 16e simulator showed the restored cream background, black heading/waveform/action button and neutral voice badge. No voice session or backend game was started for the visual check; the temporary device was removed afterward.
