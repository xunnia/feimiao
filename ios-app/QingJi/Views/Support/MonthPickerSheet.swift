import SwiftUI

/// Shared month selector for the home and statistics screens.
struct MonthPickerSheet: View {
    @Binding var selection: Date
    let maximumDate: Date
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var month: Int

    init(selection: Binding<Date>, maximumDate: Date, onConfirm: @escaping () -> Void) {
        _selection = selection
        self.maximumDate = maximumDate
        self.onConfirm = onConfirm
        let calendar = Calendar.current
        let selected = calendar.dateComponents([.year, .month], from: selection.wrappedValue)
        let maximumYear = calendar.component(.year, from: maximumDate)
        _year = State(initialValue: min(max(selected.year ?? maximumYear, 2015), maximumYear))
        _month = State(initialValue: selected.month ?? 1)
    }

    static func selectedMonth(year: Int, month: Int, maximumDate: Date,
                              calendar: Calendar = .current) -> Date {
        let maximum = calendar.dateComponents([.year, .month], from: maximumDate)
        let finalYear = min(max(year, 2015), maximum.year ?? year)
        let finalMonth = finalYear == maximum.year
            ? min(max(month, 1), maximum.month ?? month)
            : min(max(month, 1), 12)
        return calendar.date(from: DateComponents(year: finalYear, month: finalMonth, day: 1))
            ?? calendar.startOfDay(for: maximumDate)
    }

    var body: some View {
        let maximumYear = Calendar.current.component(.year, from: maximumDate)
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年份", selection: $year) {
                    ForEach(2015...max(maximumYear, 2015), id: \.self) { value in
                        Text(verbatim: "\(value)年").tag(value)
                    }
                }
                Picker("月份", selection: $month) {
                    ForEach(1...12, id: \.self) { value in
                        Text(verbatim: "\(value)月").tag(value)
                    }
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .liquidGlassCircleControl(size: 40)
                    .accessibilityLabel("取消")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") {
                        selection = Self.selectedMonth(year: year, month: month,
                                                       maximumDate: maximumDate)
                        onConfirm()
                    }
                    .liquidGlassPillControl(horizontalPadding: 12, minHeight: 40)
                }
            }
            .onChange(of: year) { _, newYear in
                if newYear == maximumYear {
                    month = min(month, Calendar.current.component(.month, from: maximumDate))
                }
            }
            .onChange(of: month) { _, newMonth in
                if year == maximumYear && newMonth > Calendar.current.component(.month, from: maximumDate) {
                    month = Calendar.current.component(.month, from: maximumDate)
                }
            }
        }
    }
}
