import SwiftUI
import AVFoundation

struct VideoAIReviewView: View {
    let store: AppStore
    let video: LocalVideo
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var working = false
    @State private var stage = ""
    @State private var error: String?
    @State private var draft: VideoReviewDraft?
    @State private var request: Task<Void, Never>?
    @State private var reviewedStart: Double = 0
    @State private var reviewedEnd: Double = 0
    @State private var saved = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "Coaching review", subtitle: "One segment. One clear focus.").boxEntrance()
                BoxInlineNotice(text: "Choose up to 30 seconds. Asking for a review sends 12 resized, timestamped still frames for AI analysis. The video file and audio are not uploaded. Sparse frames cannot establish punch counts, reaction speed, contact or a technique score.", symbol: "sparkles", color: BoxStyle.coach)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        BoxFeatureLabel(title: "Segment", symbol: "timeline.selection", color: BoxStyle.coach)
                        Spacer()
                        Text("Clip \(duration, format: .number.precision(.fractionLength(1))) sec").font(.caption).foregroundStyle(BoxStyle.muted)
                    }
                    HStack(spacing: 10) {
                        segmentField("Start", value: $start)
                        Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim)
                        segmentField("End", value: $end)
                    }
                }.boxPanel(padding: 18, tint: BoxStyle.coach).boxEntrance(1)
                if working {
                    HStack(spacing: 10) { ProgressView().tint(BoxStyle.coach); Text(stage).font(.subheadline); Spacer()
                        Button("Cancel") { request?.cancel() }.font(.subheadline.weight(.semibold)) }
                        .boxPanel(tint: BoxStyle.coach)
                } else {
                    PrimaryButton(title: "Review selected frames", symbol: "sparkles") { review() }
                        .disabled(!start.isFinite || !end.isFinite || start < 0 || end <= start || end > duration || end - start > 30)
                }
                if let error { BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
                if let draft {
                    AIReportContent(store: store, draft: draft, start: reviewedStart, end: reviewedEnd)
                    PrimaryButton(title: saved ? "Report saved" : "Save AI report", symbol: "checkmark") {
                        saved = store.saveReport(video: video, start: reviewedStart, end: reviewedEnd, model: QwenDeveloperConfiguration.visionModel, draft: draft)
                        if saved { BoxHaptics.success() }
                    }.disabled(saved)
                }
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Video review").navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                duration = try await AVURLAsset(url: store.videoURL(video)).load(.duration).seconds
                if !duration.isFinite || duration <= 0 { duration = 0; error = "This clip's duration could not be read." }
                end = min(30, duration)
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { request?.cancel() }
    }
    private func segmentField(_ label: LocalizedStringResource, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).boxEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("0", value: value, format: .number).keyboardType(.decimalPad).boxNumber(26)
                Text("sec").font(.caption2).foregroundStyle(BoxStyle.muted)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
    private func review() {
        guard QwenClient().isConfigured else { error = QwenError.notConfigured.localizedDescription; return }
        let from = start, to = end, url = store.videoURL(video)
        working = true; error = nil; draft = nil; saved = false; stage = "Preparing selected frames…"
        request = Task { @MainActor in
            defer { working = false }
            do {
                let frames = try await VideoFrames.extract(url: url, start: from, end: to)
                try Task.checkCancellation(); stage = "Your coach is reviewing the selected frames…"
                let result = try await QwenClient().reviewVideo(frames: frames, start: from, end: to)
                try Task.checkCancellation(); reviewedStart = from; reviewedEnd = to; draft = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct SavedAIReportView: View {
    let store: AppStore
    let report: AIClipReport
    @State private var draft: VideoReviewDraft?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let draft { AIReportContent(store: store, draft: draft, start: report.startSeconds, end: report.endSeconds) }
                if let error { BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Saved frame review").navigationBarTitleDisplayMode(.inline)
        .task {
            do { draft = try JSONDecoder().decode(VideoReviewDraft.self, from: report.payload) }
            catch { self.error = "This saved report could not be opened." }
        }
    }
}

private struct AIReportContent: View {
    let store: AppStore
    let draft: VideoReviewDraft
    let start: Double
    let end: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BoxChip(text: "AI observations · Unverified", symbol: "sparkles", color: BoxStyle.coach)
            Text("Sparse frames from \(start, format: .number.precision(.fractionLength(1)))–\(end, format: .number.precision(.fractionLength(1))) sec. Observations refer to visible stills, not continuously observed motion.")
                .font(.footnote).foregroundStyle(BoxStyle.muted)
            Text(draft.summary).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(draft.observations) { item in
                HStack(alignment: .top, spacing: 12) {
                    Text(item.seconds, format: .number.precision(.fractionLength(1))).boxNumber(18).foregroundStyle(BoxStyle.coach)
                        .frame(minWidth: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.observation).font(.headline)
                        Text(item.suggestion).font(.subheadline)
                        Text(item.uncertainty).font(.footnote).foregroundStyle(BoxStyle.muted)
                        if let id = item.drillID, let drill = ActivityCatalog.find(id) {
                            NavigationLink { ActivityDetailView(store: store, activity: drill) } label: {
                                Label("Related practice", systemImage: "figure.boxing").font(.subheadline.weight(.semibold))
                            }.buttonStyle(BoxSecondaryStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(BoxStyle.surface, in: .rect(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .leading) { Capsule().fill(BoxStyle.coach).frame(width: 3).padding(.vertical, 16) }
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(BoxStyle.border) }
            }
        }
    }
}
