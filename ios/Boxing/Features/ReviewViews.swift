import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ReviewLibraryView: View {
    let store: AppStore
    @Binding var sheet: AppSheet?
    @State private var importing = false
    @State private var importingStudy = false
    @State private var studyVideo: LocalVideo?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        let studies = store.styleStudies
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    BoxPageHeader(title: "Review", subtitle: "Watch your rounds back. Fix one thing.")
                    if !store.videos.isEmpty {
                        Menu {
                            Button("Record practice", systemImage: "camera") { sheet = .camera }
                            Button("Import video", systemImage: "square.and.arrow.down") { importing = true }
                        } label: {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(BoxStyle.ink)
                                .frame(width: 40, height: 40).boxGlassControl(cornerRadius: 20)
                        }
                        .accessibilityLabel("Add practice clip").disabled(busy)
                    }
                }.boxEntrance()
                ReviewIntroduction(compact: !store.videos.isEmpty, record: { sheet = .camera }, importClip: { importing = true })
                    .disabled(busy).boxEntrance(1)
                StudyFighterCard(active: store.styleFocus) { importingStudy = true }.disabled(busy).boxEntrance(2)
                if store.videos.isEmpty {
                    BoxSectionHeader(title: "How it works").padding(.top, 12).boxEntrance(2)
                    HStack(spacing: 8) {
                        ReviewStep(number: 1, symbol: "camera.fill", title: "Record", detail: "A round on your phone")
                        ReviewStep(number: 2, symbol: "sparkles", title: "Review", detail: "Scores and the fix that matters")
                        ReviewStep(number: 3, symbol: "figure.boxing", title: "Drill", detail: "Practise the fix, see it improve")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .boxEntrance(3)
                }
                if busy {
                    HStack(spacing: 10) { ProgressView().tint(BoxStyle.coach); Text("Importing clip…").font(.subheadline) }
                        .frame(maxWidth: .infinity, alignment: .leading).boxPanel()
                }
                if let error { BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent) }
                if !studies.isEmpty {
                    BoxSectionHeader(title: "Fighter studies") { Text(studies.count, format: .number) }
                        .padding(.top, 12).boxEntrance(2)
                    BoxRowGroup {
                        ForEach(studies, id: \.report.id) { item in
                            NavigationLink { SavedAIReportView(store: store, report: item.report) } label: {
                                BoxRow(symbol: "person.fill.viewfinder", color: BoxStyle.strength, title: item.style.isRejected ? String(localized: "Study not possible") : item.style.fighter,
                                       subtitle: item.style.isRejected ? (item.style.rejectReason ?? "") : "\(item.style.archetype) · \(item.report.date.formatted(.dateTime.month(.abbreviated).day()))") {
                                    if store.styleFocus?.fighter == item.style.fighter { BoxChip(text: "Focus", color: BoxStyle.strength) }
                                }
                            }.buttonStyle(BoxPressStyle(scale: 0.985))
                        }
                    }.boxEntrance(3)
                }
                let clips = store.videos.filter { $0.kind != "Fighter study" }
                if !clips.isEmpty {
                    BoxSectionHeader(title: "Your clips") { Text(clips.count, format: .number) }
                        .padding(.top, 12).boxEntrance(2)
                    BoxRowGroup {
                        ForEach(clips) { video in
                            NavigationLink { VideoDetailView(store: store, video: video) } label: {
                                ReviewClipRow(video: video, reviewed: store.reports.contains { $0.videoID == video.id && $0.kind != "style-1" }, notes: store.markers.filter { $0.videoID == video.id }.count)
                            }.buttonStyle(BoxPressStyle(scale: 0.985))
                        }
                    }.boxEntrance(3)
                }
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Review").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $studyVideo) { video in ClipAnalysisView(store: store, video: video, purpose: .style) }
        .fileImporter(isPresented: $importingStudy, allowedContentTypes: [.movie]) { result in importClip(result, kind: "Fighter study") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in importClip(result, kind: "Unsorted") }
    }

    private func importClip(_ result: Result<URL, Error>, kind: String) {
            switch result {
            case .failure(let failure): error = failure.localizedDescription
            case .success(let url):
                busy = true; error = nil
                Task { @MainActor in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() }; busy = false }
                    do {
                        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard bytes <= 500_000_000 else { error = "Choose a clip smaller than 500 MB."; return }
                        let asset = AVURLAsset(url: url)
                        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { error = "This file does not contain a playable video track."; return }
                        if !(await store.saveVideo(from: url, title: url.deletingPathExtension().lastPathComponent, kind: kind)) { error = store.storageNotice; return }
                        if kind == "Fighter study" { studyVideo = store.videos.first { $0.kind == kind } }
                    } catch { self.error = "The clip could not be imported. \(error.localizedDescription)" }
                }
            }
    }
}

/// Entry to the style study: learn to fight like someone from their footage.
private struct StudyFighterCard: View {
    let active: StyleFocus?
    let start: () -> Void
    var body: some View {
        Button(action: start) {
            HStack(spacing: 14) {
                BoxIconWell(symbol: "person.fill.viewfinder", size: 48, color: BoxStyle.strength)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Study a fighter").font(.headline)
                    Text(active.map { "Training toward \($0.fighter). Import footage to study someone else." } ?? "Import footage of any boxer. Get their style broken down and a program to fight like them.")
                        .font(.caption).foregroundStyle(BoxStyle.muted).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim)
            }
            .foregroundStyle(BoxStyle.ink)
            .boxPanel(padding: 16, tint: BoxStyle.strength)
        }
        .buttonStyle(BoxPressStyle())
    }
}

private struct ReviewIntroduction: View {
    var compact = false
    let record: () -> Void
    let importClip: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Your clips · Coach review", systemImage: "viewfinder").boxEyebrow(.white.opacity(0.85))
            Text("See it.\nFix it.").boxDisplay(compact ? 34 : 40, relativeTo: .title).padding(.top, 10)
            if !compact {
                Text("Record a round. Your coach scores it, picks the fix that matters most and gives you the drills.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.82)).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(action: record) { Label("Record", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(BoxHeroButtonStyle())
                Button(action: importClip) { Label("Import", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                    .buttonStyle(BoxHeroButtonStyle(kind: .ghost))
            }.padding(.top, 18)
            Text("Clips stay on this iPhone. A review sends a few short image strips and the measurements, never the video.")
                .font(.caption2).foregroundStyle(.white.opacity(0.7)).padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .boxHero(ropes: false)
        .overlay { ViewfinderCorners().padding(10).allowsHitTesting(false) }
    }
}

private struct ReviewStep: View {
    let number: Int
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BoxIconWell(symbol: symbol, size: 34, color: number == 3 ? BoxStyle.coach : BoxStyle.accent)
                Spacer()
                Text("\(number)").boxNumber(18).foregroundStyle(BoxStyle.dim)
            }
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(BoxStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .boxPanel(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// Camera viewfinder brackets used on Review surfaces.
struct ViewfinderCorners: View {
    var body: some View {
        Canvas { context, size in
            let l: CGFloat = 18
            var path = Path()
            path.move(to: CGPoint(x: 0, y: l)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: l, y: 0))
            path.move(to: CGPoint(x: size.width - l, y: 0)); path.addLine(to: CGPoint(x: size.width, y: 0)); path.addLine(to: CGPoint(x: size.width, y: l))
            path.move(to: CGPoint(x: size.width, y: size.height - l)); path.addLine(to: CGPoint(x: size.width, y: size.height)); path.addLine(to: CGPoint(x: size.width - l, y: size.height))
            path.move(to: CGPoint(x: l, y: size.height)); path.addLine(to: CGPoint(x: 0, y: size.height)); path.addLine(to: CGPoint(x: 0, y: size.height - l))
            context.stroke(path, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct ReviewClipRow: View {
    let video: LocalVideo
    let reviewed: Bool
    let notes: Int
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [BoxStyle.surfaceHigh, BoxStyle.surfaceRaised], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(BoxStyle.borderStrong) }
                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.75))
            }
            .frame(width: 62, height: 46)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(video.kind) · \(video.date.formatted(.dateTime.month(.abbreviated).day()))\(notes > 0 ? " · \(notes) notes" : "")")
                    .font(.caption).foregroundStyle(BoxStyle.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if reviewed { BoxChip(text: "Reviewed", color: BoxStyle.coach) }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(BoxStyle.dim)
        }
        .foregroundStyle(BoxStyle.ink)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(.rect)
    }
}

private struct VideoDetailView: View {
    let store: AppStore
    let video: LocalVideo
    @State private var player: AVPlayer?
    @State private var title = ""
    @State private var kind = "Unsorted"
    @State private var notes = ""
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var subjectCode = ""
    @State private var setupCode = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    if let player { VideoPlayer(player: player) }
                    else { ProgressView("Opening clip…").tint(BoxStyle.coach) }
                }
                .frame(maxWidth: .infinity).frame(height: 300)
                .background(BoxStyle.surface)
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(BoxStyle.borderStrong) }
                .overlay { ViewfinderCorners().padding(12).allowsHitTesting(false).opacity(player == nil ? 1 : 0) }
                .boxEntrance()
                ClipMetadataEditor(title: $title, kind: $kind, notes: $notes, saved: saved) {
                    saved = store.updateVideo(video, title: title, kind: kind, notes: notes, subjectCode: subjectCode, setupCode: setupCode)
                    if saved { BoxHaptics.success() }
                }
                ClipReviewActions(store: store, video: video)
                ClipEvaluationDetails(subjectCode: $subjectCode, setupCode: $setupCode)
                Button("Delete clip", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }.boxPage()
        }
        .scrollDismissesKeyboard(.interactively).boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Your clip").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task { title = video.title; kind = video.kind; notes = video.notes; subjectCode = video.subjectCode; setupCode = video.setupCode; player = AVPlayer(url: store.videoURL(video)) }
        .onDisappear { player?.pause(); player = nil }
        .onChange(of: subjectCode) { _, _ in saved = false }
        .onChange(of: setupCode) { _, _ in saved = false }
        .onChange(of: title) { _, _ in saved = false }
        .onChange(of: kind) { _, _ in saved = false }
        .onChange(of: notes) { _, _ in saved = false }
        .confirmationDialog("Delete this clip and its notes?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete clip", role: .destructive) { player?.pause(); if store.deleteVideo(video) { dismiss() } }
        }
    }
}

private struct ClipMetadataEditor: View {
    @Binding var title: String
    @Binding var kind: String
    @Binding var notes: String
    let saved: Bool
    let save: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Your clip")
            TextField("Title", text: $title).font(.headline)
                .padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
            Picker("Training", selection: $kind) {
                ForEach(["Unsorted", "Shadowboxing", "Bag", "Pads", "Real sparring"], id: \.self) { Text($0).tag($0) }
            }
            TextField("What did you notice?", text: $notes, axis: .vertical).lineLimit(4...12)
                .padding(12).background(BoxStyle.surfaceRaised, in: .rect(cornerRadius: 14, style: .continuous))
            Text("Your own observations. No technique score is measured.").font(.caption).foregroundStyle(BoxStyle.muted)
            PrimaryButton(title: saved ? "Changes saved" : "Save changes", symbol: "checkmark", action: save)
                .disabled(saved || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.boxPanel()
    }
}

private struct ClipReviewActions: View {
    let store: AppStore
    let video: LocalVideo
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink { ClipAnalysisView(store: store, video: video, purpose: .review) } label: {
                BoxRow(symbol: "sparkles", color: BoxStyle.coach, title: String(localized: "Coach review"),
                       subtitle: String(localized: "Scores, fixes and drills for this clip"))
                    .boxPanel(padding: 0, tint: BoxStyle.coach)
            }.buttonStyle(BoxPressStyle())
            NavigationLink { ClipAnalysisView(store: store, video: video, purpose: .style) } label: {
                BoxRow(symbol: "person.fill.viewfinder", color: BoxStyle.strength, title: String(localized: "Study the fighter in this clip"),
                       subtitle: String(localized: "Break down their style and train like them"))
                    .boxPanel(padding: 0)
            }.buttonStyle(BoxPressStyle())
            ForEach(store.reports.filter { $0.videoID == video.id }) { report in
                NavigationLink { SavedAIReportView(store: store, report: report) } label: { SavedReportRow(report: report) }
                    .buttonStyle(BoxPressStyle())
            }
            NavigationLink { VideoMarkersView(store: store, video: video) } label: {
                BoxRow(symbol: "bookmark.fill", color: BoxStyle.timer, title: String(localized: "Timestamped labels & notes"),
                       subtitle: String(localized: "Mark moments by hand"))
                    .boxPanel(padding: 0)
            }.buttonStyle(BoxPressStyle())
        }
    }
}

private struct SavedReportRow: View {
    let report: AIClipReport
    var body: some View {
        let date = report.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        Group {
            if let style = report.style {
                BoxRow(symbol: "person.fill.viewfinder", color: BoxStyle.strength, title: style.isRejected ? String(localized: "Study not possible") : style.fighter, subtitle: date)
            } else if let review = report.review {
                BoxRow(symbol: "doc.text.magnifyingglass", color: BoxStyle.coach, title: review.isRejected ? String(localized: "Review not possible") : review.headline, subtitle: date) {
                    if let score = review.scores?.overall { Text("\(score)").boxNumber(20).foregroundStyle(BoxStyle.coach) }
                }
            } else {
                BoxRow(symbol: "doc.text.magnifyingglass", color: BoxStyle.coach, title: String(localized: "Earlier frame review"), subtitle: date)
            }
        }
        .boxPanel(padding: 0)
    }
}

private struct ClipEvaluationDetails: View {
    @Binding var subjectCode: String
    @Binding var setupCode: String
    var body: some View {
        DisclosureGroup("Evaluation clip details") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Anonymous person code, e.g. boxer-01", text: $subjectCode)
                TextField("Setup code, e.g. room-a-front", text: $setupCode)
                Text("Optional codes for preparing evaluation clips. Labels describe observed movement, never the requested cue. Use Save changes above to keep edits.").font(.caption).foregroundStyle(BoxStyle.muted)
            }.padding(.top, 12)
        }.font(.subheadline).boxPanel()
    }
}

private struct VideoMarkersView: View {
    let store: AppStore
    let video: LocalVideo
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var action = "Uncertain / occluded"
    @State private var note = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                if let player { VideoPlayer(player: player).frame(height: 240) }
                Text("Pause and mark only what you can see. These are manual annotations, not model predictions or coach-reviewed technique labels.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("New interval") {
                HStack {
                    Text("Start (sec)")
                    TextField("0", value: $start, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Button("Here") { start = max(0, player?.currentTime().seconds ?? 0) }
                }
                HStack {
                    Text("End (sec)")
                    TextField("0", value: $end, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Button("Here") { end = min(duration, player?.currentTime().seconds ?? 0) }
                }
                Picker("Observed action", selection: $action) {
                    ForEach(["Jab", "Cross", "Jab–cross", "Idle / reset", "Other movement", "Uncertain / occluded"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Observation or correction to work on", text: $note, axis: .vertical)
                Button("Save manual annotation") {
                    if store.addMarker(video: video, start: start, end: end, duration: duration, action: action, note: note) { note = "" }
                }.disabled(!start.isFinite || !end.isFinite || start < 0 || end <= start || end > duration)
                if let error { Text(error).foregroundStyle(BoxStyle.accent) }
            }
            Section("Your annotations") {
                ForEach(store.markers.filter { $0.videoID == video.id }) { marker in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(marker.action).font(.headline)
                        Text("\(marker.startSeconds, format: .number.precision(.fractionLength(2)))–\(marker.endSeconds, format: .number.precision(.fractionLength(2))) sec · Manual")
                            .font(.caption).foregroundStyle(.secondary)
                        if !marker.note.isEmpty { Text(marker.note).font(.subheadline) }
                        HStack {
                            Button("Jump here") { player?.seek(to: CMTime(seconds: marker.startSeconds, preferredTimescale: 600)) }
                            Spacer()
                            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteMarker(marker) }.labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
        .boxFormStyle(tint: BoxStyle.timer)
        .navigationTitle("Clip annotations").navigationBarTitleDisplayMode(.inline)
        .task {
            let asset = AVURLAsset(url: store.videoURL(video))
            do {
                duration = try await asset.load(.duration).seconds
                if !duration.isFinite || duration <= 0 { error = "This clip's duration could not be read."; duration = 0 }
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { player?.pause(); player = nil }
    }
}
