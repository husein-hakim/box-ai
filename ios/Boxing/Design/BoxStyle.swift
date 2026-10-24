import SwiftUI

// MARK: - Tokens

/// BOX "Ringside" design tokens. One brand red, four pillar colors that always mean the same thing,
/// charcoal surfaces for content and native glass for floating controls.
enum BoxStyle {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.043)
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.086)
    static let surfaceRaised = Color(red: 0.106, green: 0.106, blue: 0.125)
    static let surfaceHigh = Color(red: 0.141, green: 0.141, blue: 0.165)
    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.12)

    static let ink = Color(red: 0.965, green: 0.953, blue: 0.933)
    static let muted = Color(red: 0.616, green: 0.604, blue: 0.588)
    static let dim = Color(red: 0.373, green: 0.365, blue: 0.353)

    /// Brand red. Primary actions, selection, boxing.
    static let accent = Color(red: 0.949, green: 0.220, blue: 0.169)
    static let button = Color(red: 0.88, green: 0.12, blue: 0.14)
    static let redGradient = LinearGradient(colors: [Color(red: 0.96, green: 0.27, blue: 0.23), Color(red: 0.85, green: 0.12, blue: 0.14)], startPoint: .top, endPoint: .bottom)

    /// Strength work, streaks and carbs.
    static let strength = Color(red: 0.961, green: 0.647, blue: 0.141)
    /// Conditioning, running and completed states.
    static let conditioning = Color(red: 0.239, green: 0.839, blue: 0.549)
    /// Coach and AI content. Always paired with an "AI estimate" style label.
    static let coach = Color(red: 0.655, green: 0.545, blue: 0.980)
    /// Timers, water, fat and defensive movement.
    static let timer = Color(red: 0.353, green: 0.784, blue: 0.980)

    static let heroGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.933, green: 0.227, blue: 0.173), location: 0),
            .init(color: Color(red: 0.769, green: 0.086, blue: 0.118), location: 0.48),
            .init(color: Color(red: 0.478, green: 0.039, blue: 0.071), location: 1)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Typography

/// Compressed italic display type for impact, condensed numerals for data, SF Pro for reading.
private struct BoxScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let width: Font.Width
    let italic: Bool
    let monospaced: Bool

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, width: Font.Width, italic: Bool, monospaced: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight; self.width = width; self.italic = italic; self.monospaced = monospaced
    }

    func body(content: Content) -> some View {
        let base = Font.system(size: size, weight: weight).width(width)
        content.font(monospaced ? base.monospacedDigit() : base)
            .modifier(BoxOblique(active: italic))
    }
}

/// SF Pro has no italic at condensed/compressed widths, so each line is slanted around its own midline.
struct BoxOblique: ViewModifier {
    var active = true
    func body(content: Content) -> some View {
        content.textRenderer(BoxObliqueRenderer(slant: active ? 0.17 : 0))
    }
}

struct BoxObliqueRenderer: TextRenderer {
    var slant: CGFloat
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var lineContext = context
            let mid = line.typographicBounds.rect.midY
            if slant != 0 { lineContext.concatenate(CGAffineTransform(a: 1, b: 0, c: -slant, d: 1, tx: slant * mid, ty: 0)) }
            lineContext.draw(line)
        }
    }
}

extension View {
    /// Uppercase compressed italic headline. Use for page titles and hero headlines.
    func boxDisplay(_ size: CGFloat = 40, relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(BoxScaledFont(size: size, relativeTo: style, weight: .black, width: .compressed, italic: true, monospaced: false))
            .textCase(.uppercase)
            .lineSpacing(-2)
    }

    /// Condensed italic section heading.
    func boxSection(_ size: CGFloat = 22) -> some View {
        modifier(BoxScaledFont(size: size, relativeTo: .title3, weight: .heavy, width: .condensed, italic: true, monospaced: false))
            .textCase(.uppercase)
    }

    /// Condensed tabular numerals that never jump while counting.
    func boxNumber(_ size: CGFloat = 32, relativeTo style: Font.TextStyle = .title, italic: Bool = false) -> some View {
        modifier(BoxScaledFont(size: size, relativeTo: style, weight: .heavy, width: .condensed, italic: italic, monospaced: true))
    }

    /// Small uppercase tracked label above a title.
    func boxEyebrow(_ color: Color = BoxStyle.muted) -> some View {
        modifier(BoxScaledFont(size: 11, relativeTo: .caption2, weight: .bold, width: .standard, italic: false, monospaced: false))
            .textCase(.uppercase).tracking(1.6).foregroundStyle(color)
    }
}

// MARK: - Surfaces

struct BoxPanel: ViewModifier {
    var padding: CGFloat = 16
    var tint: Color?
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
                ZStack {
                    shape.fill(LinearGradient(colors: [Color(red: 0.086, green: 0.086, blue: 0.102), Color(red: 0.067, green: 0.067, blue: 0.078)], startPoint: .top, endPoint: .bottom))
                    if let tint {
                        shape.fill(RadialGradient(colors: [tint.opacity(0.16), .clear], center: .topTrailing, startRadius: 0, endRadius: 190))
                    }
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(BoxStyle.border, lineWidth: 1) }
    }
}

/// Signature red hero: gradient, canvas texture, ring-rope motif and inner highlight.
/// Only one per screen. It marks the screen's focal action.
struct BoxHeroBackground: View {
    var cornerRadius: CGFloat = 26
    var showsRopes = true
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(BoxStyle.heroGradient)
            shape.fill(RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.43).opacity(0.38), .clear], center: .topLeading, startRadius: 0, endRadius: 260))
            Canvas { context, size in
                var x: CGFloat = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height * 0.47, y: 0))
                    context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 2)
                    x += 7
                }
                guard showsRopes else { return }
                for index in 0..<3 {
                    let y = size.height - 30 - CGFloat(index) * 14
                    var rope = Path()
                    rope.move(to: CGPoint(x: size.width * 0.42, y: y + 14))
                    rope.addQuadCurve(to: CGPoint(x: size.width + 20, y: y - 6), control: CGPoint(x: size.width * 0.75, y: y + 2))
                    context.stroke(rope, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.3)]), startPoint: CGPoint(x: size.width * 0.42, y: y), endPoint: CGPoint(x: size.width, y: y)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            .clipShape(shape)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: BoxStyle.accent.opacity(0.4), radius: 22, y: 14)
        .accessibilityHidden(true)
    }
}

/// Near-black canvas with a soft colored glow behind the header.
struct BoxScreenBackground: View {
    var tint: Color = BoxStyle.accent
    var body: some View {
        BoxStyle.background
            .overlay(alignment: .top) {
                RadialGradient(colors: [tint.opacity(0.2), .clear], center: .init(x: 0.5, y: -0.1), startRadius: 0, endRadius: 420)
                    .frame(height: 460)
            }
            .ignoresSafeArea()
    }
}

extension View {
    func boxPanel(padding: CGFloat = 16, tint: Color? = nil) -> some View { modifier(BoxPanel(padding: padding, tint: tint)) }
    func boxHero(padding: CGFloat = 20, ropes: Bool = true) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background { BoxHeroBackground(showsRopes: ropes) }
            .foregroundStyle(.white)
    }
    func boxScreen(tint: Color = BoxStyle.accent) -> some View {
        background { BoxScreenBackground(tint: tint) }
    }
}

// MARK: - Buttons

/// Full-width red capsule. The single primary action of a screen.
struct BoxPrimaryStyle: ButtonStyle {
    var height: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .heavy).width(.condensed))
            .textCase(.uppercase).tracking(0.8)
            .modifier(BoxOblique())
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(isEnabled ? .white : BoxStyle.muted)
            .background {
                if isEnabled {
                    Capsule().fill(BoxStyle.redGradient)
                        .overlay { Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 1) }
                        .shadow(color: BoxStyle.accent.opacity(configuration.isPressed ? 0.25 : 0.5), radius: configuration.isPressed ? 8 : 16, y: configuration.isPressed ? 4 : 10)
                } else {
                    Capsule().fill(BoxStyle.surfaceRaised).overlay { Capsule().strokeBorder(BoxStyle.border) }
                }
            }
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed && isEnabled { BoxHaptics.impact() } }
    }
}

/// White (or translucent) capsule that sits on the red hero.
struct BoxHeroButtonStyle: ButtonStyle {
    enum Kind { case solid, ghost }
    var kind: Kind = .solid
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy).width(.condensed))
            .textCase(.uppercase).tracking(0.8)
            .modifier(BoxOblique())
            .padding(.horizontal, 22)
            .frame(minHeight: 50)
            .foregroundStyle(kind == .solid ? Color(red: 0.08, green: 0.03, blue: 0.04) : .white)
            .background {
                if kind == .solid {
                    Capsule().fill(.white).shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                } else {
                    Capsule().fill(.black.opacity(0.22)).overlay { Capsule().strokeBorder(.white.opacity(0.3)) }
                }
            }
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { BoxHaptics.impact() } }
    }
}

struct PrimaryButton: View {
    let title: LocalizedStringResource
    var symbol = "play.fill"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: symbol).font(.system(size: 15, weight: .bold)) }
        }
        .buttonStyle(BoxPrimaryStyle())
    }
}

struct BoxPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed && enabled { BoxHaptics.press() } }
    }
}

/// Neutral secondary action shared across every feature. Never uses accent-tinted capsules.
struct BoxSecondaryStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(enabled ? BoxStyle.ink : BoxStyle.muted)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(minHeight: 46)
            .background(BoxStyle.surfaceRaised, in: .capsule)
            .overlay { Capsule().strokeBorder(BoxStyle.borderStrong) }
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed && enabled { BoxHaptics.press() } }
    }
}

// MARK: - Headings and notes

struct SectionHeading: View {
    let title: LocalizedStringResource
    var body: some View {
        Text(title).boxSection().foregroundStyle(BoxStyle.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct DevelopmentNote: View {
    let text: LocalizedStringResource
    var body: some View {
        DisclosureGroup {
            Text(text).font(.footnote).foregroundStyle(BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: { Label("About this feature", systemImage: "info.circle").font(.caption.weight(.medium)).foregroundStyle(BoxStyle.muted) }
        .tint(BoxStyle.muted)
    }
}

// MARK: - Glass controls

struct GlassIconButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if #available(iOS 26, *), !reduceTransparency {
            Button(action: action) { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel(Text(label))
        } else {
            Button(action: action) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
                    .background(BoxStyle.surfaceRaised, in: .circle)
                    .overlay { Circle().strokeBorder(BoxStyle.borderStrong) }
            }
            .buttonStyle(BoxPressStyle(scale: 0.9)).accessibilityLabel(Text(label))
        }
    }
}

/// Glass capsule with an icon and a short label, e.g. "History".
struct GlassPillButton: View {
    let title: LocalizedStringResource
    let symbol: String
    var tint: Color = BoxStyle.ink
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let label = Label { Text(title) } icon: { Image(systemName: symbol) }
            .font(.footnote.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 4).frame(minHeight: 36)
        if #available(iOS 26, *), !reduceTransparency {
            Button(action: action) { label }.buttonStyle(.glass)
        } else {
            Button(action: action) {
                label.padding(.horizontal, 10)
                    .background(BoxStyle.surfaceRaised, in: .capsule)
                    .overlay { Capsule().strokeBorder(BoxStyle.borderStrong) }
            }.buttonStyle(BoxPressStyle(scale: 0.94))
        }
    }
}
