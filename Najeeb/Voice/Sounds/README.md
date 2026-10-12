# Game feedback sounds

Two small effects from [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds), released under [CC0](https://creativecommons.org/publicdomain/zero/1.0/). The original pack license is preserved in `KENNEY-LICENSE.txt`.

| App resource | Original | Duration | Use |
| --- | --- | --- | --- |
| `correct.wav` | `Audio/confirmation_001.ogg` | About 0.29 seconds | Correct answer and awarded points |
| `incorrect.wav` | `Audio/error_001.ogg` | About 0.16 seconds | Wrong answer or surrender, including bomb penalties |

The originals were converted to mono 44.1 kHz, 16-bit PCM WAV with FFmpeg, without trimming or changing pitch. Both files total about 40 KB. Native playback uses 35 percent player volume and the voice session's existing audio route.

Effects follow saved native outcomes, once per turn. Replays and reconnects do not replay an old effect. The microphone is briefly muted and the host is ducked during a cue; the app returns the answer tool result after playback finishes. A missing/failed sound never changes a score. Effects can be disabled in Settings; developer diagnostics provides two preview buttons.
