import Foundation

/// A computed result from a math expression or unit conversion query.
public struct CalculatorItem: Equatable, Hashable, Sendable {
    /// Original query string, shown as subtitle.
    public let expression: String
    /// Formatted result, shown as the row title.
    public let displayResult: String
    /// Plain value written to the clipboard on activation.
    public let copyValue: String

    public init(expression: String, displayResult: String, copyValue: String) {
        self.expression = expression
        self.displayResult = displayResult
        self.copyValue = copyValue
    }
}

/// Evaluates math expressions and unit conversions from search query strings.
public final class ExpressionCalculator: Sendable {
    public init() {}

    /// Returns a `CalculatorItem` if `query` is a recognized math expression or unit conversion,
    /// or `nil` if it should be treated as a regular search query.
    public func evaluate(query: String) -> CalculatorItem? {
        let trimmed = normalizedCalculatorQuery(query).trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        if let result = evaluateUnitConversion(trimmed) { return result }
        return evaluateMath(trimmed)
    }
}

private func normalizedCalculatorQuery(_ query: String) -> String {
    let halfWidth = query.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? query
    return halfWidth
        .replacingOccurrences(of: "×", with: "*")
        .replacingOccurrences(of: "÷", with: "/")
        .replacingOccurrences(of: "−", with: "-")
        .replacingOccurrences(of: "﹣", with: "-")
        .replacingOccurrences(of: "－", with: "-")
}

// MARK: - Math Expression

extension ExpressionCalculator {
    private func evaluateMath(_ input: String) -> CalculatorItem? {
        guard let tokens = tokenizeMath(input), !tokens.isEmpty else { return nil }

        // Skip bare numbers — not useful to surface as a calculator result.
        let hasOperator = tokens.contains { if case .op = $0 { return true }; return false }
        guard hasOperator else { return nil }

        let parser = MathParser(tokens: tokens)
        guard let value = parser.parse(), parser.isFullyConsumed, value.isFinite else { return nil }

        let formatted = formatNumber(value)
        return CalculatorItem(expression: input, displayResult: formatted, copyValue: formatted)
    }

    func formatNumber(_ value: Double) -> String {
        if abs(value) < 1e15, value == floor(value), !value.isNaN {
            return String(Int64(value))
        }
        return String(format: "%.10g", value)
    }
}

// MARK: - Math Tokenizer

private enum MathToken {
    case number(Double)
    case op(MathOp)
    case lparen
    case rparen
}

private enum MathOp: Equatable {
    case plus, minus, multiply, divide, modulo, power
}

private func tokenizeMath(_ input: String) -> [MathToken]? {
    var tokens: [MathToken] = []
    var i = input.startIndex

    while i < input.endIndex {
        let ch = input[i]
        if ch.isWhitespace { i = input.index(after: i); continue }

        if ch.isNumber || ch == "." {
            let start = i
            while i < input.endIndex && (input[i].isNumber || input[i] == ".") {
                i = input.index(after: i)
            }
            guard let value = Double(input[start..<i]) else { return nil }
            tokens.append(.number(value))
            continue
        }

        let token: MathToken
        switch ch {
        case "+": token = .op(.plus)
        case "-": token = .op(.minus)
        case "*": token = .op(.multiply)
        case "/": token = .op(.divide)
        case "%": token = .op(.modulo)
        case "^": token = .op(.power)
        case "(": token = .lparen
        case ")": token = .rparen
        default: return nil
        }
        tokens.append(token)
        i = input.index(after: i)
    }

    return tokens
}

// MARK: - Math Parser (recursive descent, standard precedence)

private final class MathParser {
    private let tokens: [MathToken]
    private var pos: Int = 0

    init(tokens: [MathToken]) { self.tokens = tokens }

    var isFullyConsumed: Bool { pos == tokens.count }

    func parse() -> Double? { parseAddSub() }

    private func peek() -> MathToken? { pos < tokens.count ? tokens[pos] : nil }

    private func consume() { if pos < tokens.count { pos += 1 } }

    private func parseAddSub() -> Double? {
        guard var left = parseMulDiv() else { return nil }
        while let t = peek(), case .op(let op) = t, op == .plus || op == .minus {
            consume()
            guard let right = parseMulDiv() else { return nil }
            left = op == .plus ? left + right : left - right
        }
        return left
    }

    private func parseMulDiv() -> Double? {
        guard var left = parsePow() else { return nil }
        while let t = peek(), case .op(let op) = t,
              op == .multiply || op == .divide || op == .modulo {
            consume()
            guard let right = parsePow() else { return nil }
            switch op {
            case .multiply: left = left * right
            case .divide:
                guard right != 0 else { return nil }
                left = left / right
            case .modulo:
                guard right != 0 else { return nil }
                left = left.truncatingRemainder(dividingBy: right)
            default: break
            }
        }
        return left
    }

    // Right-associative exponentiation.
    private func parsePow() -> Double? {
        guard let base = parseUnary() else { return nil }
        if let t = peek(), case .op(let op) = t, op == .power {
            consume()
            guard let exp = parsePow() else { return nil }
            return pow(base, exp)
        }
        return base
    }

    private func parseUnary() -> Double? {
        if let t = peek(), case .op(let op) = t, op == .minus || op == .plus {
            consume()
            guard let value = parseUnary() else { return nil }
            return op == .minus ? -value : value
        }
        return parseAtom()
    }

    private func parseAtom() -> Double? {
        guard let t = peek() else { return nil }
        if case .number(let v) = t { consume(); return v }
        if case .lparen = t {
            consume()
            guard let v = parseAddSub() else { return nil }
            guard case .rparen? = peek() else { return nil }
            consume()
            return v
        }
        return nil
    }
}

// MARK: - Unit Conversion

private struct UnitConversionResult {
    let value: Double
    let unitLabel: String
}

extension ExpressionCalculator {
    private func evaluateUnitConversion(_ input: String) -> CalculatorItem? {
        // Matches: <number>[optional space]<unit> (in|to) <unit>
        // e.g. "100cm in inch", "72 °F to celsius", "5km in miles"
        let pattern = #"^(-?\d+(?:\.\d+)?)\s*([a-zA-Z°µ²³/]+)\s+(?:in|to)\s+([a-zA-Z°µ²³/]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let nsRange = NSRange(input.startIndex..., in: input)
        guard let match = regex.firstMatch(in: input, range: nsRange) else { return nil }

        guard
            let r1 = Range(match.range(at: 1), in: input),
            let r2 = Range(match.range(at: 2), in: input),
            let r3 = Range(match.range(at: 3), in: input),
            let value = Double(input[r1])
        else { return nil }

        let fromUnit = String(input[r2]).lowercased()
        let toUnit   = String(input[r3]).lowercased()

        guard let converted = convert(value: value, from: fromUnit, to: toUnit) else { return nil }

        let resultNumber = formatNumber(converted.value)
        let displayResult = "\(resultNumber) \(converted.unitLabel)"
        return CalculatorItem(expression: input, displayResult: displayResult, copyValue: resultNumber)
    }

    private func convert(value: Double, from: String, to: String) -> UnitConversionResult? {
        if let r = convertLength(value, from, to)      { return r }
        if let r = convertMass(value, from, to)        { return r }
        if let r = convertTemperature(value, from, to) { return r }
        if let r = convertTime(value, from, to)        { return r }
        if let r = convertVolume(value, from, to)      { return r }
        if let r = convertSpeed(value, from, to)       { return r }
        return nil
    }

    // MARK: Length (base: meters)

    private static let lengthUnits: [String: (factor: Double, label: String)] = [
        "mm": (0.001, "mm"), "millimeter": (0.001, "mm"), "millimeters": (0.001, "mm"),
        "cm": (0.01, "cm"), "centimeter": (0.01, "cm"), "centimeters": (0.01, "cm"),
        "m": (1.0, "m"), "meter": (1.0, "m"), "meters": (1.0, "m"), "metre": (1.0, "m"), "metres": (1.0, "m"),
        "km": (1_000.0, "km"), "kilometer": (1_000.0, "km"), "kilometers": (1_000.0, "km"),
        "in": (0.0254, "in"), "inch": (0.0254, "in"), "inches": (0.0254, "in"),
        "ft": (0.3048, "ft"), "foot": (0.3048, "ft"), "feet": (0.3048, "ft"),
        "yd": (0.9144, "yd"), "yard": (0.9144, "yd"), "yards": (0.9144, "yd"),
        "mi": (1_609.344, "mi"), "mile": (1_609.344, "mi"), "miles": (1_609.344, "mi"),
    ]

    private func convertLength(_ value: Double, _ from: String, _ to: String) -> UnitConversionResult? {
        guard let f = Self.lengthUnits[from], let t = Self.lengthUnits[to] else { return nil }
        return UnitConversionResult(value: value * f.factor / t.factor, unitLabel: t.label)
    }

    // MARK: Mass (base: grams)

    private static let massUnits: [String: (factor: Double, label: String)] = [
        "mg": (0.001, "mg"), "milligram": (0.001, "mg"), "milligrams": (0.001, "mg"),
        "g": (1.0, "g"), "gram": (1.0, "g"), "grams": (1.0, "g"),
        "kg": (1_000.0, "kg"), "kilogram": (1_000.0, "kg"), "kilograms": (1_000.0, "kg"),
        "lb": (453.592, "lb"), "lbs": (453.592, "lb"), "pound": (453.592, "lb"), "pounds": (453.592, "lb"),
        "oz": (28.3495, "oz"), "ounce": (28.3495, "oz"), "ounces": (28.3495, "oz"),
        "st": (6_350.29, "st"), "stone": (6_350.29, "st"), "stones": (6_350.29, "st"),
    ]

    private func convertMass(_ value: Double, _ from: String, _ to: String) -> UnitConversionResult? {
        guard let f = Self.massUnits[from], let t = Self.massUnits[to] else { return nil }
        return UnitConversionResult(value: value * f.factor / t.factor, unitLabel: t.label)
    }

    // MARK: Temperature (offset-based)

    private static let tempUnits: Set<String> = ["°c", "c", "celsius", "°f", "f", "fahrenheit", "k", "kelvin"]

    private func convertTemperature(_ value: Double, _ from: String, _ to: String) -> UnitConversionResult? {
        guard Self.tempUnits.contains(from), Self.tempUnits.contains(to) else { return nil }

        let kelvin: Double
        switch from {
        case "°c", "c", "celsius":    kelvin = value + 273.15
        case "°f", "f", "fahrenheit": kelvin = (value - 32) * 5.0 / 9.0 + 273.15
        case "k", "kelvin":           kelvin = value
        default: return nil
        }

        let result: Double; let label: String
        switch to {
        case "°c", "c", "celsius":    result = kelvin - 273.15;               label = "°C"
        case "°f", "f", "fahrenheit": result = (kelvin - 273.15) * 9.0 / 5.0 + 32; label = "°F"
        case "k", "kelvin":           result = kelvin;                         label = "K"
        default: return nil
        }

        return UnitConversionResult(value: result, unitLabel: label)
    }

    // MARK: Time (base: seconds)

    private static let timeUnits: [String: (factor: Double, label: String)] = [
        "ms": (0.001, "ms"), "millisecond": (0.001, "ms"), "milliseconds": (0.001, "ms"),
        "s": (1.0, "s"), "second": (1.0, "s"), "seconds": (1.0, "s"), "sec": (1.0, "s"), "secs": (1.0, "s"),
        "min": (60.0, "min"), "minute": (60.0, "min"), "minutes": (60.0, "min"), "mins": (60.0, "min"),
        "h": (3_600.0, "h"), "hr": (3_600.0, "h"), "hour": (3_600.0, "h"), "hours": (3_600.0, "h"), "hrs": (3_600.0, "h"),
        "day": (86_400.0, "days"), "days": (86_400.0, "days"),
        "week": (604_800.0, "weeks"), "weeks": (604_800.0, "weeks"),
        "month": (2_592_000.0, "months"), "months": (2_592_000.0, "months"),
        "year": (31_536_000.0, "years"), "years": (31_536_000.0, "years"),
    ]

    private func convertTime(_ value: Double, _ from: String, _ to: String) -> UnitConversionResult? {
        guard let f = Self.timeUnits[from], let t = Self.timeUnits[to] else { return nil }
        return UnitConversionResult(value: value * f.factor / t.factor, unitLabel: t.label)
    }

    // MARK: Volume (base: liters)

    private static let volumeUnits: [String: (factor: Double, label: String)] = [
        "ml": (0.001, "ml"), "milliliter": (0.001, "ml"), "milliliters": (0.001, "ml"),
        "millilitre": (0.001, "ml"), "millilitres": (0.001, "ml"),
        "l": (1.0, "L"), "liter": (1.0, "L"), "liters": (1.0, "L"), "litre": (1.0, "L"), "litres": (1.0, "L"),
        "tsp": (0.00492892, "tsp"), "teaspoon": (0.00492892, "tsp"), "teaspoons": (0.00492892, "tsp"),
        "tbsp": (0.0147868, "tbsp"), "tablespoon": (0.0147868, "tbsp"), "tablespoons": (0.0147868, "tbsp"),
        "cup": (0.236588, "cups"), "cups": (0.236588, "cups"),
        "pt": (0.473176, "pt"), "pint": (0.473176, "pt"), "pints": (0.473176, "pt"),
        "qt": (0.946353, "qt"), "quart": (0.946353, "qt"), "quarts": (0.946353, "qt"),
        "gal": (3.78541, "gal"), "gallon": (3.78541, "gal"), "gallons": (3.78541, "gal"),
    ]

    private func convertVolume(_ value: Double, _ from: String, _ to: String) -> UnitConversionResult? {
        guard let f = Self.volumeUnits[from], let t = Self.volumeUnits[to] else { return nil }
        return UnitConversionResult(value: value * f.factor / t.factor, unitLabel: t.label)
    }

    // MARK: Speed (base: m/s)

    private static let speedUnits: [String: (factor: Double, label: String)] = [
        "m/s": (1.0, "m/s"),
        "km/h": (1.0 / 3.6, "km/h"), "kph": (1.0 / 3.6, "km/h"), "kmh": (1.0 / 3.6, "km/h"),
        "mph": (0.44704, "mph"),
        "knot": (0.514444, "knots"), "knots": (0.514444, "knots"), "kn": (0.514444, "knots"),
    ]

    private func convertSpeed(_ value: Double, _ from: String, _ to: String) -> UnitConversionResult? {
        guard let f = Self.speedUnits[from], let t = Self.speedUnits[to] else { return nil }
        return UnitConversionResult(value: value * f.factor / t.factor, unitLabel: t.label)
    }
}
