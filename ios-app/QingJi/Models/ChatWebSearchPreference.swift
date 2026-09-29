import Foundation

/// 聊天 [+] 面板里的「联网搜索」开关，全 App 只有这一个（对齐安卓
/// `ai_chat_web_search_enabled`，默认开）。账号编辑页不再单独放联网开关。
enum ChatWebSearchPreference {
    static let key = "qingji.chatWebSearchEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
