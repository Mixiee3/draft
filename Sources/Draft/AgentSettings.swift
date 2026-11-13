import SwiftUI
import DraftCore

/// Settings › Agents: per-client permissions and what agents recently read or proposed.
struct AgentSettings: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var activity: [AgentActivity.Entry] = []

    var clients: [String] {
        Array(Set(model.library.settings.agentPermissions.keys).union(activity.map(\.client))).filter { !$0.isEmpty }.sorted()
    }

    func binding(_ client: String, _ key: WritableKeyPath<AgentPermission, Bool>) -> Binding<Bool> {
        Binding(get: { model.library.settings.agentPermission(client)[keyPath: key] },
                set: { v in model.setSettings { var p = $0.agentPermission(client); p[keyPath: key] = v; $0.agentPermissions[client] = p } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Connected agents", footer: "Agents such as Codex or Claude Code connect through scripts/draft-mcp.sh. They never change notes themselves: every change is a proposal you review. New agents can read and propose; destructive changes (deleting content, replacing a whole note, moving notes) stay off until you allow them.") {
                if clients.isEmpty {
                    Text("No agent has connected yet.").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(DS.s3 + 2)
                }
                ForEach(clients, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text).padding(.horizontal, DS.s3 + 2).padding(.top, DS.s2)
                        SettingsSwitchRow(title: "Read notes", isOn: binding(c, \.read))
                        SettingsSwitchRow(title: "Propose changes", detail: "Edits, new notes and renames, shown for review", isOn: binding(c, \.propose))
                        SettingsSwitchRow(title: "Destructive changes", detail: "Deleting blocks, replacing a whole note, moving notes", isOn: binding(c, \.destructive))
                    }
                    .accessibilityElement(children: .contain).accessibilityLabel("Permissions for \(c)")
                }
            }
            SettingsSection(title: "Recent activity", footer: "Kept on this Mac: tool, note and time only, never note text. The last 1,000 entries are kept.") {
                if activity.isEmpty { Text("Nothing yet.").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(DS.s3 + 2) }
                ForEach(Array(activity.suffix(30).reversed().enumerated()), id: \.offset) { _, e in
                    SettingsRow(title: "\(e.client) · \(e.tool.replacingOccurrences(of: "draft_", with: "").replacingOccurrences(of: "_", with: " "))",
                                detail: e.document.flatMap { model.library.docs[$0]?.title }.map { LocalizedStringKey($0.isEmpty ? "Untitled" : $0) }) {
                        Text(Date(timeIntervalSince1970: e.time / 1000).formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: appLocale))).font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
                    }
                }
                if !activity.isEmpty {
                    SettingsRow(title: "Clear activity") { Button("Clear") { AgentActivity.clear(model.vault.dir); activity = [] }.buttonStyle(DraftButtonStyle(compact: true)) }
                }
            }
        }
        .task { activity = await Task.detached { [dir = model.vault.dir] in AgentActivity.entries(dir) }.value }
    }
}
