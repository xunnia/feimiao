import Foundation
import SwiftUI

/// 连接电脑上的本地模型伴侣。iOS 只允许本机回环地址，不能把明文 HTTP
/// 扩展成远程连接器。
struct LocalModelCompanionView: View {
    @AppStorage("qingji.ai.localCompanion.enabled") private var enabled = false
    @AppStorage("qingji.ai.localCompanion.endpoint") private var endpoint = "http://127.0.0.1:8787"
    @AppStorage("qingji.ai.localCompanion.model") private var model = ""
    @State private var isChecking = false
    @State private var health: Bool?
    @State private var message: String?

    private var endpointURL: URL? {
        URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var endpointIsSafe: Bool {
        guard let url = endpointURL,
              url.scheme?.lowercased() == "http" else { return false }
        let host = url.host?.lowercased() ?? ""
        return ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    var body: some View {
        Form {
            Section("本地模型伴侣") {
                Toggle("启用本地模型", isOn: $enabled)
                TextField("地址", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("模型名称（可选）", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button {
                    checkHealth()
                } label: {
                    if isChecking {
                        ProgressView()
                    } else {
                        Label("检查本地服务", systemImage: "waveform.path.ecg")
                    }
                }
                .disabled(isChecking || !endpointIsSafe)
                if let health {
                    Label(
                        health ? "本地伴侣服务可用" : "暂时无法连接",
                        systemImage: health ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(health ? Color.accentColor : .orange)
                }
            } footer: {
                Text(endpointIsSafe
                     ? "只访问本机回环地址；iOS 不会在后台启动电脑进程。"
                     : "地址必须是 http://localhost、127.0.0.1 或 [::1] 回环地址。")
            }
        }
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("本地模型伴侣")
        .navigationBarTitleDisplayMode(.inline)
        .alert("本地模型伴侣", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func checkHealth() {
        guard endpointIsSafe, let url = endpointURL else { return }
        isChecking = true
        health = nil
        Task { @MainActor in
            defer { isChecking = false }
            var request = URLRequest(url: url.appendingPathComponent("health"))
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    health = false
                    return
                }
                health = (200..<300).contains(http.statusCode)
            } catch {
                health = false
                message = error.localizedDescription
            }
        }
    }
}
