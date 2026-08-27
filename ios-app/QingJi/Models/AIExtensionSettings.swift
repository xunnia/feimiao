import Foundation

struct AISkillDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let isWriteCapable: Bool
}

struct AIConnectorDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let isExternal: Bool
}

enum AIExtensionCatalog {
    static let skills: [AISkillDefinition] = [
        AISkillDefinition(
            id: "ledger_assistant",
            title: "记账助手",
            subtitle: "识别、预览并写入账单；写入前需要确认。",
            isWriteCapable: true
        ),
        AISkillDefinition(
            id: "ledger_analyst",
            title: "账本分析",
            subtitle: "读取统计和账本数据，生成可解释的分析。",
            isWriteCapable: false
        ),
        AISkillDefinition(
            id: "bill_import",
            title: "账单导入",
            subtitle: "解析文件并在复核后批量归类。",
            isWriteCapable: true
        ),
        AISkillDefinition(
            id: "report_writer",
            title: "报告生成",
            subtitle: "基于当前账本生成可保存的周期报告。",
            isWriteCapable: false
        ),
    ]

    static let connectors: [AIConnectorDefinition] = [
        AIConnectorDefinition(
            id: "web_search",
            title: "联网搜索",
            subtitle: "只在打开搜索时访问公开网页。",
            isExternal: true
        ),
        AIConnectorDefinition(
            id: "local_companion",
            title: "本地模型伴侣",
            subtitle: "只允许连接本机回环地址，不访问远程 HTTP。",
            isExternal: false
        ),
    ]
}

enum AIExtensionSettings {
    private static func key(_ prefix: String, _ id: String) -> String {
        "qingji.ai.\(prefix).\(id)"
    }

    static func isSkillEnabled(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        bool(key("skill", id), defaults: defaults)
    }

    static func setSkillEnabled(_ enabled: Bool, id: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key("skill", id))
    }

    static func isConnectorEnabled(_ id: String, defaults: UserDefaults = .standard) -> Bool {
        bool(key("connector", id), defaults: defaults)
    }

    static func setConnectorEnabled(_ enabled: Bool, id: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key("connector", id))
    }

    private static func bool(_ key: String, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }
}
