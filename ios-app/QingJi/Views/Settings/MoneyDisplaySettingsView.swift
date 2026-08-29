import SwiftUI

/// 与 Android「金额显示」对应。只调整屏幕和导出前的展示，不修改账单真实金额。
struct MoneyDisplaySettingsView: View {
    private enum RoundingMode: String, CaseIterable, Identifiable {
        case round
        case ceil
        case floor
        case truncate

        var id: String { rawValue }
        var title: String {
            switch self {
            case .round: "四舍五入"
            case .ceil: "向上取整"
            case .floor: "向下取整"
            case .truncate: "直接取整"
            }
        }
        var subtitle: String {
            switch self {
            case .round: "12.50 显示为 13"
            case .ceil: "只要有小数就进一位"
            case .floor: "永远舍去到更小整数"
            case .truncate: "直接去掉小数部分"
            }
        }
    }

    @AppStorage("qingji.moneyDecimalPlaces") private var decimalPlaces = 2
    @AppStorage("qingji.moneyRoundingMode") private var roundingRaw = RoundingMode.round.rawValue

    private var roundingMode: Binding<RoundingMode> {
        Binding(
            get: { RoundingMode(rawValue: roundingRaw) ?? .round },
            set: { roundingRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("金额保留位数") {
                Picker("小数位数", selection: $decimalPlaces) {
                    Text("两位").tag(2)
                    Text("一位").tag(1)
                    Text("整数").tag(0)
                }
                .pickerStyle(.segmented)

                Text("示例：\(MoneyFormat.string(Decimal(string: "1234.56") ?? 0, currencyCode: "CNY"))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if decimalPlaces == 0 {
                Section("整数取整方式") {
                    Picker("取整方式", selection: roundingMode) {
                        ForEach(RoundingMode.allCases) { mode in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                Text(mode.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }

            Section {
                Text("只改变金额展示方式，不会修改账单真实金额和计算精度。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .liquidGlassCanvas()
        .navigationTitle("金额显示")
        .navigationBarTitleDisplayMode(.inline)
    }
}
