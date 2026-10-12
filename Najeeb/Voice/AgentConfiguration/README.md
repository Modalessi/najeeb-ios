# Najeeb ElevenLabs configuration

`system-prompt.txt` defines host behavior; `first-message.txt` is `{{session_opening}}`, supplied by the native saved-game state. `agent.json` defines twenty response-waiting client tools plus `end_call` and silent `skip_turn` (no re-prompt).

A fresh opening welcomes the players, introduces Najeeb and the two-team, eighteen-question competition, and asks directly for six categories. It does not ask which game to play. Saved games keep their existing phase-aware greeting; after naming both teams, the host introduces their matchup.

The agent judges semantic equivalence using `current_question.reference_answer`, then calls `submitAnswer(answer, is_correct, expected_question_id, turn_token)`. Swift handles points and turns. During questions, activation variants (**يا نجيب، يانجيب**, or **نجيب** alone), explicit submission phrases (**حنا نعتمد، إجابتنا هي، جوابنا هو**) and native-authorized follow-ups are supported. Calling the name opens an eight-second window for the current turn. The agent uses native context or `getGameSummary.data.voice_input` for authorization and submits the actual utterance verbatim. Discussion outside the window stays silent. The host explains this once with the first question; later questions, repeats and resumed sessions omit the reminder unless players ask. ASR keywords boost the name and submission phrases. Choices, hint and bomb are automatic per-team helpers; there is no selection step.

The current published voice/model choices are Saud / `eleven_v4_turbo` and `deepseek-v41-flash`, preserved from the dashboard's existing draft. Publish dashboard changes before reconnecting the app; local edits do not change the hosted agent.

`ProvisionAgent.swift` validates and combines the text/config files. Compile it as a standalone Swift command-line executable and run `--dry-run` to inspect the body. `--agent-id` updates an existing agent; omitting it creates an agent. A real API request requires `ELEVENLABS_API_KEY` in the developer terminal environment. Never embed this key in the iOS app or commit it. Dashboard changes do not happen merely by editing local files.

Client tool requests arrive at `conversation.$pendingToolCalls`; the app decodes arguments, validates/dispatches typed operations, saves the result, and responds using `sendToolResult(for:result:isError:)`. See the [official SDK documentation](https://elevenlabs.io/docs/eleven-agents/libraries/swift) and [silent skip-turn tool](https://elevenlabs.io/docs/eleven-agents/customization/tools/system-tools/skip-turn).


From the repository root:

```sh
xcrun swiftc -parse-as-library Najeeb/Voice/AgentConfiguration/ProvisionAgent.swift -o /tmp/najeeb-provision
/tmp/najeeb-provision --dry-run
```

The default config path is `Najeeb/Voice/AgentConfiguration/agent.json`. Supply `--config` when running from another directory. Use your own agent ID in the app settings to test your agent; API keys belong only in the provisioning utility's environment.
