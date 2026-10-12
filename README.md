# Najeeb iOS

Native Saudi Arabic voice trivia with SwiftUI, ElevenLabs Agents and a shared iPhone/CarPlay game session. The backend supplies eighteen media-free questions; the host understands conversation and judges answer meaning, while Swift controls turns, helpers, scores and the winner.

## Run

1. Open `Najeeb.xcodeproj` in Xcode and allow Swift package dependencies to resolve.
2. Choose the **Najeeb** scheme and an installed iPhone simulator, then press **⌘R**. To use a physical iPhone, select your signing team and device in Xcode.
3. Open **المزيد → الإعدادات**, sign in with a Najeeb email OTP and configure the ElevenLabs agent ID. New accounts see a name popup after OTP verification.
4. Press **ابدأ مع نجيب** and allow microphone access. Choose six categories, name two teams and confirm the game through conversation.

The backend is the single constant `GameSession.baseURL` in [GameSession.swift](Najeeb/Game/GameSession.swift): `https://najeb-production.up.railway.app/`. Change it and rebuild to target a development server. The UI exposes the agent ID and sound toggle. The prototype's default public agent ID can be replaced with your own; see [agent configuration](Najeeb/Voice/AgentConfiguration/README.md). No ElevenLabs API key is embedded in the application.

## Source layout

```text
Najeeb/
  NajeebApp.swift
  Game/       # engine, state, tool routing, shared session
  API/        # backend requests and question validation
  Voice/      # activation, audio, sounds, agent configuration
  Storage/    # settings and saved game
  Views/      # SwiftUI screens, theme and fonts
  CarPlay/    # native scene, plist and entitlement
```

All app code belongs to one Xcode target. There are no local `NajeebCore` or `NajeebContent` application dependencies. ElevenLabs Swift SDK **3.4.0** and LiveKit **2.17.0** are pinned in the Xcode project and shared lockfile. The root `Package.swift` exposes the same engine/API/activation sources only for isolated tests.

## Gameplay

Six categories run in easy, medium and hard order for eighteen questions, with alternating teams. Each team automatically receives **خيارات، تلميح، القنبلة**, once each. The host introduces answer activation once with the first question:

- **يا نجيب، إجابتنا هي جواز السفر**
- **يانجيب، نبي تلميح** — merged and misspelled activation variants are normalized.
- **إجابتنا هي جواز السفر** / **حنا نعتمد جواز السفر** — explicit submissions also activate.
- **يا نجيب**, followed by an answer/helper request within eight seconds.

Ordinary team discussion is ignored. Repeating preserves the current question. Successful answers and surrender automatically prepare the next question; replayed calls cannot double-award points. Pause/reconnect restores the game. Quit changes the main action to **ابدأ لعبة جديدة**. Diagnostics contains transcripts, state and tool results.

## Backend contracts

- `GET /game/categories`: available categories.
- `POST /users/login`, `/users/check_otp`, `/users/logout`: cookie authentication.
- `POST /game/carmode_questions`: eighteen unique questions, six categories × 100/300/500 points. All question media, including sound, is excluded; answer media is ignored.
- `POST /game/question/choices`, `/game/question/hint`: helper content. Failures do not consume a helper.

The Go backend and React frontend are separate repositories and are not included here. A working backend, account access and a correctly published ElevenLabs agent are required for a live game.

## Test and build

From this repository root:

```sh
swift test
./scripts/build-native.sh
./scripts/build-native.sh Najeeb-CarPlay
```

The three suites under `Tests/` cover game rules, voice activation and mock HTTP contracts. Xcode is required to build the app; the Swift package alone does not build its interface or voice SDK. See [verification](docs/VERIFICATION.md) and the [spoken acceptance matrix](docs/VOICE_TEST_MATRIX.md).

## CarPlay

The **Najeeb-CarPlay** scheme uses `CPVoiceControlTemplate` and the same `GameSession.shared`. It targets iOS 26.4+ and requires Apple's voice-conversation CarPlay entitlement. Building this scheme does not establish entitlement approval or working CarPlay runtime. CarPlay has not been verified in an actual simulator; use the regular iPhone scheme for voice-game testing.

## Walkthroughs

- [How the app works, its flow and code](docs/APP_WALKTHROUGH.md)
- [How ElevenLabs agents, settings and tools work](docs/ELEVENLABS_WALKTHROUGH.md)

Short correct/incorrect cues are [Kenney CC0 interface sounds](https://kenney.nl/assets/interface-sounds); attribution and the original license are in [Voice/Sounds](Najeeb/Voice/Sounds/README.md). The UI uses Najeeb's frontend colors and bundled Thmanyah Sans fonts.
