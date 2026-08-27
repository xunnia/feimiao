import Foundation

/// AI 数据发送授权按服务商隔离保存。切换 provider 时必须重新确认；
/// 同一个 provider 内切换模型不重复要求授权。
enum AIPrivacyConsentStore {
    private static let defaultsKey = "qingji.ai.privacy-consent.v1"

    static func isAccepted(for providerID: UUID, defaults: UserDefaults = .standard) -> Bool {
        let values = defaults.stringArray(forKey: defaultsKey) ?? []
        return values.contains(providerID.uuidString)
    }

    static func accept(for providerID: UUID, defaults: UserDefaults = .standard) {
        var values = defaults.stringArray(forKey: defaultsKey) ?? []
        let id = providerID.uuidString
        if !values.contains(id) {
            values.append(id)
            defaults.set(values, forKey: defaultsKey)
        }
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
