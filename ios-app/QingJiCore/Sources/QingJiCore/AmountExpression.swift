import Foundation

/// 快记键盘的金额输入模型，支持连加/连减（如 12+3.5-2）。
/// 不变式：`parts` 始终非空，最后一项是正在编辑的数字。
public struct AmountExpression: Equatable, Sendable {
    public static let maxIntegerDigits = 9
    public static let maxFractionDigits = 2

    private var parts: [String] = [""]
    private var operators: [Character] = []

    public init() {}

    public var isEmpty: Bool { parts == [""] }

    /// 是否是多段相加的表达式（UI 据此显示 "=合计"）。
    public var isCompound: Bool { parts.count > 1 }

    /// 表达式合计金额。
    public var value: Decimal {
        guard let first = parts.first else { return 0 }
        var result = Decimal(string: first) ?? 0
        for index in 1..<parts.count {
            let value = Decimal(string: parts[index]) ?? 0
            result = operators[index - 1] == "-" ? result - value : result + value
        }
        return result
    }

    /// 键盘上方展示的原始表达式文本，如 "12+3.5"。
    public var displayText: String {
        guard !isEmpty else { return "0" }
        var output = parts[0]
        for index in operators.indices {
            output.append(operators[index])
            output.append(parts[index + 1])
        }
        return output
    }

    public mutating func insertDigit(_ digit: Character) {
        guard digit.isNumber else { return }
        var current = parts[parts.count - 1]
        if let dotIndex = current.firstIndex(of: ".") {
            let fractionCount = current.distance(from: current.index(after: dotIndex), to: current.endIndex)
            guard fractionCount < Self.maxFractionDigits else { return }
        } else {
            guard current.count < Self.maxIntegerDigits else { return }
            if current == "0" { current = "" }
        }
        current.append(digit)
        parts[parts.count - 1] = current
    }

    public mutating func insertDot() {
        var current = parts[parts.count - 1]
        guard !current.contains(".") else { return }
        if current.isEmpty { current = "0" }
        current.append(".")
        parts[parts.count - 1] = current
    }

    /// 按下 "+"：结束当前数字，开始输入下一段。当前段为空时忽略。
    public mutating func beginAddition() {
        beginOperation("+")
    }

    /// 按下 "−"：结束当前数字，开始输入下一段。当前段为空时忽略。
    public mutating func beginSubtraction() {
        beginOperation("-")
    }

    private mutating func beginOperation(_ operation: Character) {
        guard Decimal(string: parts[parts.count - 1]) != nil else { return }
        operators.append(operation)
        parts.append("")
    }

    public mutating func deleteBackward() {
        var current = parts[parts.count - 1]
        if current.isEmpty {
            if parts.count > 1 {
                parts.removeLast()
                operators.removeLast()
            }
        } else {
            current.removeLast()
            parts[parts.count - 1] = current
        }
    }

    public mutating func clear() {
        parts = [""]
        operators = []
    }
}
