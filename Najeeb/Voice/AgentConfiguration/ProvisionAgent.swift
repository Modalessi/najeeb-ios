import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct Options {
    var configurationPath = "Najeeb/Voice/AgentConfiguration/agent.json"
    var agentID: String?
    var voiceID: String?
    var dryRun = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            if option == "--dry-run" {
                dryRun = true
            } else if ["--config", "--agent-id", "--voice-id"].contains(option) {
                index += 1
                guard index < arguments.count, !arguments[index].isEmpty else {
                    throw ProvisionError.usage("Missing value for \(option).")
                }
                switch option {
                case "--config": configurationPath = arguments[index]
                case "--agent-id": agentID = arguments[index]
                default: voiceID = arguments[index]
                }
            } else {
                throw ProvisionError.usage("Unknown argument: \(option).")
            }
            index += 1
        }
        if let agentID, agentID.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }) {
            throw ProvisionError.usage("Agent ID must contain only letters, numbers, underscores or hyphens.")
        }
    }
}

private enum ProvisionError: LocalizedError {
    case usage(String)
    case invalidConfiguration(String)
    case missingAPIKey
    case httpFailure(Int)
    case missingAgentID

    var errorDescription: String? {
        switch self {
        case .usage(let message), .invalidConfiguration(let message): return message
        case .missingAPIKey: return "Set ELEVENLABS_API_KEY in this terminal environment. Never add it to the iOS app or source control."
        case .httpFailure(let status): return "ElevenLabs returned HTTP \(status). Check account permissions, supported voice/model and configuration in the dashboard. No automatic retry was attempted."
        case .missingAgentID: return "Provider succeeded but returned no agent_id. Inspect the dashboard before creating again."
        }
    }
}

@main
private struct ProvisionAgent {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            let configurationURL = URL(fileURLWithPath: options.configurationPath)
            let sourceData = try Data(contentsOf: configurationURL)
            guard var configuration = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
                  var conversation = configuration["conversation_config"] as? [String: Any],
                  var agent = conversation["agent"] as? [String: Any],
                  var prompt = agent["prompt"] as? [String: Any],
                  let tools = prompt["tools"] as? [[String: Any]], !tools.isEmpty else {
                throw ProvisionError.invalidConfiguration("Configuration must contain agent.prompt.tools.")
            }

            let directory = configurationURL.deletingLastPathComponent()
            prompt["prompt"] = try String(contentsOf: directory.appendingPathComponent("system-prompt.txt"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            agent["first_message"] = try String(contentsOf: directory.appendingPathComponent("first-message.txt"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var toolNames = Set<String>()
            for tool in tools {
                guard tool["type"] as? String == "client", tool["expects_response"] as? Bool == true,
                      let name = tool["name"] as? String, toolNames.insert(name).inserted,
                      let parameters = tool["parameters"] as? [String: Any], parameters["type"] as? String == "object" else {
                    throw ProvisionError.invalidConfiguration("Each tool must be a unique response-waiting client tool with an object schema.")
                }
            }

            agent["prompt"] = prompt
            conversation["agent"] = agent
            if let voiceID = options.voiceID ?? ProcessInfo.processInfo.environment["ELEVENLABS_VOICE_ID"], !voiceID.isEmpty {
                var tts = conversation["tts"] as? [String: Any] ?? [:]
                tts["voice_id"] = voiceID
                conversation["tts"] = tts
            }
            configuration["conversation_config"] = conversation
            let requestBody = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            if options.dryRun {
                FileHandle.standardOutput.write(requestBody)
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }

            guard let apiKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !apiKey.isEmpty else {
                throw ProvisionError.missingAPIKey
            }
            let endpoint: URL
            if let agentID = options.agentID {
                endpoint = URL(string: "https://api.elevenlabs.io/v1/convai/agents/\(agentID)")!
            } else {
                endpoint = URL(string: "https://api.elevenlabs.io/v1/convai/agents/create")!
            }
            var request = URLRequest(url: endpoint)
            request.httpMethod = options.agentID == nil ? "POST" : "PATCH"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.httpBody = requestBody
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ProvisionError.invalidConfiguration("No HTTP response. Inspect the dashboard before retrying creation.")
            }
            guard (200..<300).contains(response.statusCode) else {
                throw ProvisionError.httpFailure(response.statusCode)
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard let agentID = body?["agent_id"] as? String ?? options.agentID else {
                throw ProvisionError.missingAgentID
            }
            print("\(options.agentID == nil ? "Created" : "Updated") Najeeb agent: \(agentID)")
            print("Dashboard: https://elevenlabs.io/app/agents/agents/\(agentID)")
            print("Set this agent ID in the app settings. Audition the account voice in Saudi Arabic before voice acceptance testing.")
        } catch {
            let message = "Provisioning failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }
}
