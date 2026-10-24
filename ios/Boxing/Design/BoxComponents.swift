import SwiftUI
import UIKit

// MARK: - Model
@MainActor enum BoxHaptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func press() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45) }
    static func impact() { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7) }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}

// MARK: - Page structure

/// 01 · Header. Compressed italic title, one line saying what the screen is for.
struct BoxPageHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).boxDisplay(42).foregroundStyle(BoxStyle.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(BoxStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section heading with an optional trailing detail or action.
struct BoxSectionHeader<Trailing: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).boxSection().foregroundStyle(BoxStyle.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing.font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.muted)
        }
        .padding(.horizontal, 2)
    }
}

extension BoxSectionHeader where Trailing == EmptyView {
    init(title: LocalizedStringResource) { self.title = title; self.trailing = EmptyView() }
}

// MARK: - Atoms

struct BoxIconWell: View {
    let symbol: String
    var size: CGFloat = 40
    var color: Color = BoxStyle.accent
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.15), in: .rect(cornerRadius: size * 0.31, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: size * 0.31, style: .continuous).strokeBorder(color.opacity(0.28), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

struct BoxChip: View {
    let text: LocalizedStringResource
    var symbol: String?
    var color: Color?
    var onHero = false
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color ?? (onHero ? .white : BoxStyle.ink))
        .padding(.horizontal, 10).frame(minHeight: 26)
        .background((onHero ? Color.black.opacity(0.18) : (color ?? .white).opacity(color == nil ? 0.07 : 0.12)), in: .capsule)
        .overlay { Capsule().strokeBorder(onHero ? .white.opacity(0.2) : (color ?? .white).opacity(color == nil ? 0.08 : 0.32), lineWidth: 1) }
    }
}

/// Verbatim-string chip for dynamic values such as durations.
struct BoxValueChip: View {
    let text: String
    var onHero = false
    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(onHero ? .white : BoxStyle.ink)
            .padding(.horizontal, 10).frame(minHeight: 26)
            .background(onHero ? Color.black.opacity(0.18) : .white.opacity(0.07), in: .capsule)
            .overlay { Capsule().strokeBorder(onHero ? .white.opacity(0.2) : .white.opacity(0.08), lineWidth: 1) }
    }
}

struct BoxFeatureLabel: View {
    let title: LocalizedStringResource
    let symbol: String
    var color: Color = BoxStyle.accent
    var body: some View {
        Label { Text(title) } icon: { Image(systemName: symbol) }
            .boxEyebrow(color)
    }
}

/// Animated ring used for progress, timers and goals.
struct BoxRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6
    var color: Color = BoxStyle.accent
    var track: Color = .white.opacity(0.08)
    var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private var fraction: Double { progress.isFinite ? min(1, max(0, progress)) : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown || reduceMotion ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? color.opacity(0.7) : .clear, radius: glow ? 8 : 0)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: fraction)
        .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85).delay(0.1), value: shown)
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}

struct BoxProgressTrack: View {
    let value: Double
    var color: Color = BoxStyle.accent
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(color).frame(width: geometry.size.width * (shown || reduceMotion ? fraction : 0))
            }
        }.frame(height: height)
            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: fraction)
            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.15), value: shown)
            .onAppear { shown = true }
            .accessibilityHidden(true)
    }
}

// MARK: - Molecules

/// 03 · Tool card. Tinted icon well, title and subtitle on charcoal.
struct BoxActionTile: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    var color: Color = BoxStyle.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                BoxIconWell(symbol: symbol, color: color)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(BoxStyle.ink)
                Text(subtitle).font(.caption).foregroundStyle(BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
        .boxPanel(tint: color)
        .contentShape(.rect(cornerRadius: 22))
    }
}

/// Compact stat: icon + eyebrow, big number, optional unit and progress.
struct BoxStatTile: View {
    let label: LocalizedStringResource
    let value: String
    var unit: LocalizedStringResource?
    var symbol: String?
    var color: Color = BoxStyle.accent
    var progress: Double?
    var caption: LocalizedStringResource?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(color) }
                Text(label).boxEyebrow(symbol == nil ? BoxStyle.muted : color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value).boxNumber(32).foregroundStyle(BoxStyle.ink)
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(.footnote).foregroundStyle(BoxStyle.muted) }
            }
            if let progress { BoxProgressTrack(value: progress, color: color) }
            if let caption { Text(caption).font(.caption2).foregroundStyle(BoxStyle.muted) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .boxPanel(padding: 14, tint: symbol == nil ? nil : color)
        .accessibilityElement(children: .combine)
    }
}

/// 04 · History row. Use inside `BoxRowGroup`.
struct BoxRow<Trailing: View>: View {
    let symbol: String
    var color: Color = BoxStyle.accent
    let title: String
    var subtitle: String?
    var showsChevron = true
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            BoxIconWell(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.ink)
                    .multilineTextAlignment(.leading)
                if let subtitle { Text(verbatim: subtitle).font(.caption).foregroundStyle(BoxStyle.muted).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 6)
            trailing
            if showsChevron { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

extension BoxRow where Trailing == EmptyView {
    init(symbol: String, color: Color = BoxStyle.accent, title: String, subtitle: String? = nil, showsChevron: Bool = true) {
        self.symbol = symbol; self.color = color; self.title = title; self.subtitle = subtitle; self.showsChevron = showsChevron
        self.trailing = EmptyView()
    }
}

/// One charcoal card holding a stack of rows separated by hairlines.
struct BoxRowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                    if index > 0 { Rectangle().fill(BoxStyle.border).frame(height: 1).padding(.leading, 66) }
                    subview
                }
            }
        }
        .boxPanel(padding: 0)
    }
}

struct BoxEmptyState: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BoxIconWell(symbol: symbol, size: 46)
            Text(title).boxSection(24).foregroundStyle(BoxStyle.ink)
            Text(detail).font(.subheadline).foregroundStyle(BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).boxPanel(padding: 18)
    }
}

struct BoxInlineNotice: View {
    let text: LocalizedStringResource
    var symbol = "info.circle"
    var color: Color = BoxStyle.muted
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(color) }
            .font(.footnote).foregroundStyle(BoxStyle.muted)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(BoxStyle.surfaceRaised.opacity(0.7), in: .rect(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BoxStyle.border) }
            .accessibilityElement(children: .combine)
    }
}

/// Pill segmented control with a sliding selection and selection haptic.
struct BoxSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> LocalizedStringResource
    var symbol: ((Value) -> String)?
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    guard !selected else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) { selection = option }
                    BoxHaptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        if let symbol { Image(systemName: symbol(option)).font(.system(size: 13, weight: .semibold)) }
                        Text(title(option)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(selected ? BoxStyle.ink : BoxStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [BoxStyle.surfaceHigh, BoxStyle.surfaceRaised], startPoint: .top, endPoint: .bottom))
                                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)) }
                                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(BoxStyle.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(BoxStyle.border) }
    }
}

// MARK: - Modifiers

private struct BoxGlassControl: ViewModifier {
    var cornerRadius: CGFloat = 28
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: cornerRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(BoxStyle.borderStrong) }
        }
    }
}

/// Rise-and-settle entrance. `order` staggers siblings into a cascade.
private struct BoxEntrance: ViewModifier {
    var order: Int = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.98, anchor: .top)
            .onAppear {
                guard !appeared else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.84).delay(0.04 + Double(order) * 0.06)) { appeared = true }
            }
    }
}

extension View {
    func boxGlassControl(cornerRadius: CGFloat = 28) -> some View { modifier(BoxGlassControl(cornerRadius: cornerRadius)) }
    func boxEntrance(_ order: Int = 0) -> some View { modifier(BoxEntrance(order: order)) }

    /// Standard page frame for scrolling content: padding, glow background, ink text.
    func boxPage(tint: Color = BoxStyle.accent) -> some View {
        self.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
    }

    /// Dark grouped styling for native `Form` and `List` screens.
    func boxFormStyle(tint: Color = BoxStyle.accent) -> some View {
        self.scrollContentBackground(.hidden)
            .boxScreen(tint: tint)
    }

    /// Row background for native `Form` / `List` sections.
    func boxRowBackground() -> some View {
        listRowBackground(BoxStyle.surface)
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            BoxPageHeader(title: "Train", subtitle: "Pick a practice. Put in the rounds.")
            VStack(alignment: .leading, spacing: 10) {
                Text("Today · Reaction").boxEyebrow(.white.opacity(0.8))
                Text("Read. React. Reset.").boxDisplay(38)
                Button("Start session") {}.buttonStyle(BoxHeroButtonStyle())
            }.boxHero()
            HStack {
                BoxActionTile(title: "Round timer", subtitle: "Bell · rounds · rest", symbol: "timer", color: BoxStyle.timer)
                BoxActionTile(title: "Coach", subtitle: "Ask anything", symbol: "bubble.left.and.text.bubble.right", color: BoxStyle.coach)
            }
            PrimaryButton(title: "Start round 1") {}
        }.padding(20)
    }.boxScreen().preferredColorScheme(.dark)
}
