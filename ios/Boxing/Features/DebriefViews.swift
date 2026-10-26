import SwiftUI

/// "What was good, what to work on, what's next", right after a session.
struct CoachDebriefCard: View {
    let store: AppStore
    let recordID: UUID
    /// Dark glass styling for the sparring overlay.
    var onDark = false
    @State private var debrief: SessionDebrief?
    @State private var writing = false
    @State private var adjustment: SessionAdjustment?
    @State private var next: PlannedPractice?
    @State private var applied: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(BoxStyle.coach)
                    .frame(width: 28, height: 28).background(BoxStyle.coach.opacity(0.18), in: .circle)
                Text("Coach's debrief").boxEyebrow(BoxStyle.coach)
                Spacer()
                if writing { ProgressView().controlSize(.small).tint(BoxStyle.coach) }
            }
            if let debrief {
                Text(debrief.headline).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                ForEach(debrief.good) { point(symbol: "checkmark.circle.fill", color: BoxStyle.conditioning, $0) }
                ForEach(debrief.workOn) { point(symbol: "scope", color: BoxStyle.strength, $0) }
                Text(debrief.next).font(.subheadline).foregroundStyle(onDark ? .white.opacity(0.8) : BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let adjustment, let next, applied == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Update \(next.displayTitle)?", systemImage: "arrow.triangle.2.circlepath").font(.subheadline.weight(.semibold))
                    Text(adjustment.summary).font(.caption).foregroundStyle(onDark ? .white.opacity(0.75) : BoxStyle.muted)
                    HStack(spacing: 8) {
                        Button { applied = store.apply(adjustment, to: next); if applied == true { BoxHaptics.success() } } label: { Text("Apply").frame(maxWidth: .infinity) }
                            .buttonStyle(BoxSecondaryStyle())
                        Button { applied = false } label: { Text("Keep as planned").frame(maxWidth: .infinity) }
                            .buttonStyle(BoxSecondaryStyle())
                    }
                }
                .padding(12).background(onDark ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(BoxStyle.surfaceRaised), in: .rect(cornerRadius: 14))
            } else if applied == true {
                Label("Next session updated.", systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(BoxStyle.conditioning)
            }
        }
        .padding(16)
        .background(onDark ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(BoxStyle.surface), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(BoxStyle.coach.opacity(0.3)) }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: debrief)
        .task { await load() }
    }

    private func point(symbol: String, color: Color, _ p: SessionDebrief.Point) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.subheadline.weight(.semibold))
                Text(p.detail).font(.caption).foregroundStyle(onDark ? .white.opacity(0.75) : BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        guard debrief == nil, let record = store.history.first(where: { $0.id == recordID }) else { return }
        let context = store.debriefContext(for: record)
        next = context.next; adjustment = context.adjustment
        if let saved = record.debrief { debrief = saved; return }
        debrief = context.auto
        guard QwenClient().isConfigured else { store.saveDebrief(context.auto, for: recordID); return }
        writing = true
        defer { writing = false }
        let prompt = context.facts.prompt(profile: store.profileSummary, nextSession: context.next?.displayTitle, adjustment: context.adjustment?.summary, reviewFocus: store.reviewFocus)
        let final = (try? await QwenClient().debrief(prompt: prompt)) ?? context.auto
        debrief = final
        store.saveDebrief(final, for: recordID)
    }
}
