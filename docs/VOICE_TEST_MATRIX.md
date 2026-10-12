# Current voice acceptance checks

Use real backend content and a connected microphone. During an open question, call **يا نجيب** or submit with a clear phrase such as **حنا نعتمد** or **إجابتنا هي**. A name-only activation allows a separate answer/helper request within eight seconds. Synthetic core tests verify transcript/state behavior, not microphone recognition or model judgments.

| Scenario | Expected result |
| --- | --- |
| Category suggestions / several choices / replacement | Actual catalog IDs; six distinct choices; correct remaining count. |
| Team creation / rename / early start | Two teams; setup confirmation required; no helper-selection questions. |
| Equivalent full answer | Agent accepts جواز السفر for جواز in passport context and submits an explicit boolean verdict. |
| Submission variants | حنا نعتمد الرياض، إجابتنا هي الرياض، جوابنا هو الرياض work without the name; Swift preserves the actual transcript even if the model sends its matching extracted answer. |
| Name variants and position | يا نجيب، يانجيب، ينجيب، ي نجيب work at the start or after earlier discussion; diacritics/punctuation and آآآ hesitation do not block the call. |
| Recorded failure regression | «وهذي فيها شوية بق كذا. أعطيني فرصة أصلح عليها، بس أنا لازم الظاهر تكون، آآآ، مـ-مرتبة. يا نجيب، إجابتنا هي جار.» authorizes the request; tool answer «جار» matches; history retains the complete actual transcript. |
| Quoted or partial names | «قال يا نجيب الرياض»، «تقولون آآآ يا نجيب إجابتنا هي جار»، «يانجيبة» and «ينجيبون» do not authorize a request; inspect real transcripts for false activations. |
| Separate activation | يا نجيب, pause, then answer or نبي تلميح within eight seconds; no incorrect answer for the name itself. |
| Expired / consumed activation | Bare answers after eight seconds, a handled request, pause/resume, reconnect or bomb turn transfer are ignored. |
| Unactivated answer / helper request / group discussion | Agent calls skip_turn with no spoken reply; no question resolution or helper consumed. وش رايكم نعتمد الرياض؟ and يمكن الرياض do not activate. |
| Addressed uncertain or overlapping speech | Clarify one final answer without resolving. |
| Addressed repeat / score / turn | Same pending question and team; no advancement. |
| Choices / hint | Backend-generated content read aloud; once per team; failure does not spend a helper. |
| Bomb | Other team answers; correct +normal points, incorrect/surrender -normal points; no second bomb for same question. |
| Pause / restart connection | Same question, scores and history; saved-game greeting, no fresh category setup. |
| Quit / New Game | Early end retains scores without a winner; primary action becomes New Game. |
| Duplicate / stale tool | Cached result or explicit rejection; never duplicate score/progression. |
| Automatic progression | Answer question two, then remain silent. Host announces the outcome and reads question three without «كمل»/«عطني السؤال». Repeat for wrong answers and surrender; no extra question or score on duplicate calls. |
| Final answer | Engine finishes at eighteen and reports winner/tie. |
| Correct / wrong feedback | One short confirmation after a saved correct answer; one error cue after wrong/surrender, including bomb deductions. Host proceeds after the cue, microphone returns to its prior state, and score/history are unchanged by playback itself. |
| Feedback replay / reconnect / Stop | Duplicate calls and restored old outcomes do not repeat a cue. Stop during a cue releases playback and preserves the committed game. |
| Effects setting / preview | Settings toggle persists independently of account/service settings. Diagnostics previews both cues without resolving a question; verify actual phone/Bluetooth volume and routes. |
| Phone layout | Verify the cream canvas, black buttons, neutral cards and readable text. Inspect 390×844 portrait and 844×390 landscape, including long questions, four choices, hint and last result. Main action remains reachable; no horizontal overflow; Arabic labels remain readable. |
