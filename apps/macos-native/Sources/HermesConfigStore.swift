import Foundation

struct HermesSkill: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let path: URL
}

@MainActor
final class HermesConfigStore: ObservableObject {
    @Published var configText = ""
    @Published var cronText = ""
    @Published var soulText = ""
    @Published var userText = ""
    @Published var skills: [HermesSkill] = []
    @Published var selectedSkill: HermesSkill?
    @Published var selectedSkillText = ""
    @Published var status = ""

    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var hermesRoot: URL {
        home.appending(path: ".hermes", directoryHint: .isDirectory)
    }

    private var configURL: URL {
        hermesRoot.appending(path: "config.yaml")
    }

    private var cronURL: URL {
        hermesRoot.appending(path: "cron/jobs.json")
    }

    private var soulURL: URL {
        hermesRoot.appending(path: "SOUL.md")
    }

    private var userURL: URL {
        hermesRoot.appending(path: "memories/USER.md")
    }

    private var skillsURL: URL {
        hermesRoot.appending(path: "skills", directoryHint: .isDirectory)
    }

    func load() {
        configText = read(configURL)
        cronText = read(cronURL)
        soulText = read(soulURL)
        userText = read(userURL)
        skills = discoverSkills()
        if selectedSkill == nil {
            selectedSkill = skills.first
        }
        loadSelectedSkill()
    }

    func saveConfig() {
        save(configText, to: configURL, label: "config.yaml")
    }

    func saveCron() {
        save(cronText, to: cronURL, label: "cron/jobs.json")
    }

    func saveSoul() {
        save(soulText, to: soulURL, label: "SOUL.md")
    }

    func saveUser() {
        save(userText, to: userURL, label: "USER.md")
    }

    func loadSelectedSkill() {
        guard let selectedSkill else {
            selectedSkillText = ""
            return
        }
        selectedSkillText = read(selectedSkill.path)
    }

    func saveSelectedSkill() {
        guard let selectedSkill else { return }
        save(selectedSkillText, to: selectedSkill.path, label: selectedSkill.name)
    }

    private func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func save(_ text: String, to url: URL, label: String) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            status = "Saved \(label)"
        } catch {
            status = "Failed to save \(label)"
        }
    }

    private func discoverSkills() -> [HermesSkill] {
        guard let enumerator = FileManager.default.enumerator(
            at: skillsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [HermesSkill] = []
        for case let url as URL in enumerator where url.lastPathComponent == "SKILL.md" {
            let relative = url.path.replacingOccurrences(of: skillsURL.path + "/", with: "")
            let parts = relative.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { continue }
            let category = parts[0]
            let name = parts[1]
            result.append(HermesSkill(id: "\(category)/\(name)", name: name, category: category, path: url))
        }
        return result.sorted { $0.id < $1.id }
    }
}
