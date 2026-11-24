import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    init(hexString: String) {
        var raw = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        self.init(hex: UInt32(value))
    }
}

enum Theme {
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let panel2 = Color(uiColor: .tertiarySystemGroupedBackground)
    static let line = Color(uiColor: .separator).opacity(0.45)
    static let line2 = Color(uiColor: .separator).opacity(0.22)
    static let text = Color.primary
    static let muted = Color.secondary
    static let soft = Color(uiColor: .tertiaryLabel)
    static let accent = Color(uiColor: .systemBlue)
    static let accent2 = Color(uiColor: .systemBlue)
    static let navy = Color(uiColor: .systemIndigo)
    static let good = Color(uiColor: .systemGreen)
    static let goodBg = good.opacity(0.14)
    static let warn = Color(uiColor: .systemOrange)
    static let warnBg = warn.opacity(0.15)
    static let bad = Color(uiColor: .systemRed)
    static let badBg = bad.opacity(0.14)
    static let marriage = Color(uiColor: .systemPink)
    static let family = Color(uiColor: .systemTeal)
    static let calendar = Color(uiColor: .systemPurple)
    static let vacation = Color(uiColor: .systemOrange)
    static let insightBg = warn.opacity(0.12)
    static let insightLine = warn.opacity(0.3)
    static let insightText = Color(uiColor: .secondaryLabel)
    static let noteBg = marriage.opacity(0.1)
    static let noteLine = marriage.opacity(0.25)
    static let noteText = marriage
    static let safeBg = accent.opacity(0.12)

    static let budgetGradient = [Color(hex: 0x60A5FA), Color(hex: 0x1E3A8A)]
    static let marriageGradient = [Color(hex: 0xF472B6), Color(hex: 0xBE185D)]
    static let familyGradient = [Color(hex: 0x2DD4BF), Color(hex: 0x0F766E)]
    static let calendarGradient = [Color(hex: 0xA78BFA), Color(hex: 0x6D28D9)]
    static let vacationGradient = [Color(hex: 0xFB923C), Color(hex: 0xC2410C)]
    static let incomeGradient = [Color(hex: 0x34D399), Color(hex: 0x15803D)]
    static let importGradient = [Color(hex: 0x38BDF8), Color(hex: 0x0369A1)]
    static let billsGradient = [Color(hex: 0x94A3B8), Color(hex: 0x334155)]
    static let aiGradient = [Color(hex: 0xF59E0B), Color(hex: 0xD97706)]
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, budget, family, calendar, more, marriage, food, vacations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .budget: return "Budget"
        case .more: return "More"
        case .marriage: return "Marriage"
        case .family: return "Family"
        case .food: return "Food"
        case .calendar: return "Calendar"
        case .vacations: return "Vacations"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .budget: return "chart.pie"
        case .more: return "ellipsis"
        case .marriage: return "heart"
        case .family: return "person.2"
        case .food: return "fork.knife"
        case .calendar: return "calendar"
        case .vacations: return "paperplane"
        }
    }

    var filled: String {
        switch self {
        case .home: return "house.fill"
        case .budget: return "chart.pie.fill"
        case .more: return "ellipsis"
        case .marriage: return "heart.fill"
        case .family: return "person.2.fill"
        case .food: return "fork.knife"
        case .calendar: return "calendar"
        case .vacations: return "paperplane.fill"
        }
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 13
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .familyGlassPanel(cornerRadius: 20)
    }
}

struct IconTile: View {
    var system: String
    var colors: [Color]
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: system)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).stroke(tint.opacity(0.12), lineWidth: 0.75))
    }

    private var tint: Color { colors.last ?? Theme.accent }
}

struct PacePill: View {
    var pace: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
    }

    private var label: String {
        switch pace {
        case "on_pace": return "On pace"
        case "watch": return "Watch"
        case "over": return "Over"
        default: return "Set budget"
        }
    }

    private var fg: Color {
        switch pace {
        case "on_pace": return Theme.good
        case "over": return Theme.bad
        default: return Theme.warn
        }
    }

    private var bg: Color {
        switch pace {
        case "on_pace": return Theme.goodBg
        case "over": return Theme.badBg
        default: return Theme.warnBg
        }
    }
}

struct SyncPill: View {
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: 0x16A34A))
                .frame(width: 6, height: 6)
                .shadow(color: Color(hex: 0x16A34A).opacity(0.35), radius: 2)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.good)
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(Theme.goodBg, in: Capsule())
    }
}

struct Avatar: View {
    var name: String
    var index: Int
    var size: CGFloat = 36

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: Color(hex: 0x0F172A).opacity(0.12), radius: 2, y: 1)
    }

    private var initial: String {
        let letter = name.trimmingCharacters(in: .whitespaces).first
        return letter.map { String($0).uppercased() } ?? "?"
    }

    private var palette: [Color] {
        let sets: [[UInt32]] = [
            [0x3B82F6, 0x1E3A8A],
            [0x2DD4BF, 0x0F766E],
            [0xA78BFA, 0x6D28D9],
            [0xFB923C, 0xC2410C]
        ]
        let pair = sets[abs(index) % sets.count]
        return pair.map { Color(hex: $0) }
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.line2, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct DonutChart: View {
    var slices: [DonutSlice]
    var totalLabel: String

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line2, lineWidth: 16)
            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.start, to: max(arc.start, arc.end))
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                Text(totalLabel)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("SPENT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.muted)
            }
            .padding(24)
        }
    }

    private var arcs: [Arc] {
        let total = slices.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }
        let gap = 0.012
        var cursor = 0.0
        return slices.map { slice in
            let span = slice.value / total
            let start = cursor + gap / 2
            let end = cursor + span - gap / 2
            cursor += span
            return Arc(id: slice.id, start: start, end: end, color: slice.color)
        }
    }

    private struct Arc: Identifiable {
        var id: String
        var start: Double
        var end: Double
        var color: Color
    }
}

struct DonutSlice: Identifiable {
    var id: String
    var name: String
    var value: Double
    var color: Color
    var label: String
}

struct Kicker: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.55)
            .foregroundStyle(Theme.muted)
    }
}

struct PrimaryButton: View {
    var title: String
    var system: String? = nil
    var action: () -> Void

    private var label: some View {
        HStack(spacing: 7) {
            if let system { Image(systemName: system) }
            Text(title)
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }

    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
        } else {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
        }
    }
}

struct OutlineButton: View {
    var title: String
    var system: String? = nil
    var action: () -> Void

    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                HStack(spacing: 7) {
                    if let system { Image(systemName: system) }
                    Text(title)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.glass)
        } else {
            Button(action: action) {
                HStack(spacing: 7) {
                    if let system { Image(systemName: system) }
                    Text(title)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.accent)
        }
    }
}

struct TintedIconButton: View {
    var system: String
    var title: String
    var tint: Color = Theme.accent
    var action: () -> Void

    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: system)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(title)
        } else {
            Button(action: action) {
                Image(systemName: system)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        }
    }
}

private struct FamilyGlassPanel: ViewModifier {
    var cornerRadius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(Theme.line, lineWidth: 0.8))
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Theme.line, lineWidth: 0.8))
        }
    }
}

extension View {
    func familyGlassPanel(cornerRadius: CGFloat) -> some View {
        modifier(FamilyGlassPanel(cornerRadius: cornerRadius))
    }
}

struct LabeledInput: View {
    var title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(text: title)
            TextField(title, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled(keyboard == .URL || keyboard == .decimalPad)
                .font(.system(size: 16, weight: .medium))
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
        }
    }
}

struct BannerToast: View {
    var text: String
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .shadow(color: Color(hex: 0x0F172A).opacity(0.08), radius: 8, y: 4)
        .padding(.horizontal, 16)
    }
}

struct GearButton: View {
    var action: () -> Void
    var body: some View {
        TintedIconButton(system: "gearshape", title: "Settings", tint: Theme.muted, action: action)
    }
}

struct Screen<Content: View>: View {
    @EnvironmentObject private var app: AppModel
    var title: String? = nil
    @ViewBuilder var content: Content
    @State private var settings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let title {
                    HStack {
                        Text(title)
                            .font(.system(size: 28, weight: .heavy))
                            .tracking(-0.6)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        GearButton { settings = true }
                    }
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .refreshable { await app.pullToRefresh() }
        .sheet(isPresented: $settings) { SettingsView() }
    }
}
