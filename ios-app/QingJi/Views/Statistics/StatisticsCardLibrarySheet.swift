import SwiftUI

struct StatisticsCardLibrarySheet: View {
    @Binding var cardOrderRaw: String
    @Environment(\.dismiss) private var dismiss

    private var visibleKeys: [String] { StatisticsCardLayout.visibleKeys(from: cardOrderRaw) }
    private var hiddenKeys: [String] {
        StatisticsCardLayout.defaultOrder.filter { !visibleKeys.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(visibleKeys, id: \.self) { key in
                        row(for: key, selected: true)
                    }
                    .onMove { source, destination in
                        guard let index = source.first else { return }
                        cardOrderRaw = StatisticsCardLayout.moved(
                            in: cardOrderRaw, from: index, to: destination
                        )
                    }
                }
                if !hiddenKeys.isEmpty {
                    Section {
                        ForEach(hiddenKeys, id: \.self) { key in
                            row(for: key, selected: false)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("自定义图表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func row(for key: String, selected: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { visibleKeys.contains(key) },
            set: { cardOrderRaw = StatisticsCardLayout.toggled(key, on: $0, in: cardOrderRaw) }
        )) {
            HStack(spacing: 6) {
                Text(StatisticsCardLayout.titles[key] ?? key)
                if StatisticsCardLayout.monthOnly.contains(key) {
                    Text("月").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.gray)
        .accessibilityLabel("\(StatisticsCardLayout.titles[key] ?? key)\(selected ? "已显示" : "已隐藏")")
    }
}
