// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Reads Antigravity session transcripts from ~/.gemini/antigravity/brain/<id>/.system_generated/logs/transcript.jsonl
struct AntigravityReader: AgentHarnessReader {
    var provider: AgentProvider { .antigravity }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard AgentLogParser.contains(line, #""source":""#) || AgentLogParser.contains(line, #""type":""#) else { return [] }
        guard let json = AgentLogParser.object(line) else { return [] }

        let date = AgentLogParser.timestamp(json["created_at"]) ?? now
        let type = json["type"] as? String ?? ""
        let source = json["source"] as? String ?? ""
        let status = json["status"] as? String ?? ""
        let stepIndex = json["step_index"] as? Int ?? 0

        // Extract project name if available in content or tool calls
        if state.project.isEmpty {
            if let content = json["content"] as? String {
                if let range = content.range(of: "Command Working Directory: ") {
                    let rest = content[range.upperBound...]
                    let cwd = String(rest.prefix { $0 != "\n" && $0 != "\r" })
                    if !cwd.isEmpty {
                        state.project = AgentLogParser.projectName(cwd)
                    }
                } else if let range = content.range(of: "Active Workspaces:\n- ") {
                    let rest = content[range.upperBound...]
                    let cwd = String(rest.prefix { $0 != "\n" && $0 != "\r" })
                    if !cwd.isEmpty {
                        state.project = AgentLogParser.projectName(cwd)
                    }
                }
            }
        }

        // If project is still empty, check tool calls for path
        if state.project.isEmpty, let toolCalls = json["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                if let args = call["args"] as? [String: Any] {
                    if let path = args["Path"] as? String ?? args["CommandLine"] as? String {
                        if path.contains("/") {
                            let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "\"'/"))
                            let components = clean.split(separator: "/")
                            if let idx = components.firstIndex(of: "Documents") ?? components.firstIndex(of: "Developer"),
                               idx + 2 < components.count {
                                state.project = AgentLogParser.native(String(components[idx + 2]))
                                break
                            }
                        }
                    }
                }
            }
        }

        // Detect model if changed
        if let content = json["content"] as? String, content.contains("Model Selection") {
            if let range = content.range(of: "setting `Model Selection` from ") {
                let rest = content[range.upperBound...]
                if let toRange = rest.range(of: " to ") {
                    let modelName = String(rest[toRange.upperBound...].prefix { $0 != "." && $0 != "\n" && $0 != "\r" })
                    if !modelName.isEmpty {
                        state.model = modelName
                    }
                }
            }
        }

        // User input begins a turn
        if type == "USER_INPUT" || source == "USER_EXPLICIT" {
            state.turnOpen = true
            return [.turnBegan(date)]
        }

        // Model planner response reports token usage
        if source == "MODEL" && type == "PLANNER_RESPONSE" {
            var entries: [AgentLogEntry] = []

            let input = AgentLogParser.int(json["input_tokens"])
            let cacheRead = AgentLogParser.int(json["cache_read_tokens"])
            let output = AgentLogParser.int(json["output_tokens"])

            if input > 0 || output > 0 || cacheRead > 0 {
                let tokens = AgentTokens(
                    input: input,
                    cacheWrite: 0,
                    cacheRead: cacheRead,
                    output: output,
                    reasoning: 0
                )
                var billable = AgentBillable()
                billable.tokens = tokens
                let rawModel = state.model.isEmpty ? "Gemini 3.8 Flash" : state.model
                let model = rawModel.components(separatedBy: " (").first ?? rawModel
                let priced = AgentPricing.cost(billable, model: model)
                let key = "antigravity:\(state.session):\(stepIndex)"
                let projectName = state.project.isEmpty ? "Antigravity" : state.project
                entries.append(.usage(
                    key: key,
                    record: AgentUsageRecord(
                        provider: .antigravity,
                        date: date,
                        model: model,
                        project: projectName,
                        session: state.session,
                        tokens: tokens,
                        cost: priced.cost,
                        savings: priced.savings
                    ),
                    billable: billable
                ))
            }

            // Check if tool calls exist in this planner response
            let toolCalls = json["tool_calls"] as? [[String: Any]] ?? []
            let hasToolCalls = !toolCalls.isEmpty

            if status == "RUNNING" || hasToolCalls {
                if state.turnOpen {
                    entries.append(.turnActive(date))
                }
            } else if status == "DONE" {
                if state.turnOpen {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: true, duration: nil))
                }
            } else if status == "ERROR" {
                if state.turnOpen {
                    state.turnOpen = false
                    entries.append(.turnEnded(date, completed: false, duration: nil))
                }
            }

            return entries
        }

        // While turn is open, other model steps (tool execution, generic) indicate active work
        if state.turnOpen {
            return [.turnActive(date)]
        }

        return []
    }
}
