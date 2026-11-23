import SwiftData
import SwiftUI

struct WrappedView: View {
    let year: Int
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @Query(sort: \ProgressPhoto.date) private var photos: [ProgressPhoto]
    @State private var page = 0
    @State private var includeWeight = false
    @State private var includePhotos = false
    @State private var share: ShareItem?
    @State private var photosUnlocked = false

    private var photosVisible: Bool { !AppSettings.shared.photoLock || photosUnlocked }

    private static let cyanCard = Color(hex: 0x7FCCF5)

    var body: some View {
        let d = WrappedData(year: year, workouts: workouts, photos: photos)
        let bg: Color = [Palette.orange, .black, Self.cyanCard, .black][page]
        let fg: Color = page == 0 || page == 2 ? .black : .white
        ZStack {
            bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(0..<4) { i in Capsule().fill(fg.opacity(i <= page ? 1 : 0.25)).frame(height: 3) }
                }
                .padding(.top, 8)
                HStack {
                    Text("YOUR \(String(year)) IN TRAINING").font(.system(size: 12, weight: .bold)).kerning(1)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)) }
                }
                .padding(.top, 18)
                Group {
                    switch page {
                    case 0: volume(d)
                    case 1: records(d)
                    case 2: running(d)
                    default: body(d)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 48)
                if page < 3 {
                    Text("Tap to continue").font(.system(size: 13)).opacity(0.6).frame(maxWidth: .infinity).padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 24)
            .foregroundStyle(fg)
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            if location.x < 110 { page = max(0, page - 1) } else if page < 3 { page += 1 }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
        .onAppear { if Wrapped.isUnlocked(year) { AppSettings.shared.wrappedSeenYear = max(AppSettings.shared.wrappedSeenYear, year) } }
        .sheet(item: $share) { ShareSheet(items: [$0.image]) }
        .statusBarHidden()
    }

    // MARK: Cards

    private func volume(_ d: WrappedData) -> some View {
        let (n, suffix) = WrappedData.big(Units.display(d.volume))
        return VStack(alignment: .leading, spacing: 0) {
            Text("You lifted").font(.system(size: 22, weight: .bold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(n)\(suffix)").font(.system(size: 88, weight: .heavy)).minimumScaleFactor(0.5).lineLimit(1)
                Text(Units.unitLabel).font(.system(size: 26, weight: .bold))
            }
            Text("across \(d.sessions) session\(d.sessions == 1 ? "" : "s").").font(.system(size: 22, weight: .bold))
            if let fact = WrappedData.volumeFact(d.volume) {
                Text(fact).font(.system(size: 19)).padding(.top, 20).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !d.groups.isEmpty {
                Text("WHERE IT WENT").font(.system(size: 12, weight: .bold)).kerning(1).padding(.bottom, 10)
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(d.groups.enumerated()), id: \.offset) { i, gr in
                            Rectangle().fill(Color.black.opacity(1 - Double(i) * 0.22)).frame(width: max(4, (g.size.width - 6) * gr.1))
                        }
                    }
                }
                .frame(height: 16).clipShape(Capsule())
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(Array(d.groups.enumerated()), id: \.offset) { _, gr in
                        HStack { Text(gr.0); Spacer(); Text("\(Int((gr.1 * 100).rounded()))%") }.font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(.top, 10).padding(.bottom, 24)
            }
        }
    }

    private func records(_ d: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(d.prCount)").font(.system(size: 110, weight: .heavy)).foregroundStyle(Palette.orange).minimumScaleFactor(0.5).lineLimit(1)
            Text("personal record\(d.prCount == 1 ? "" : "s")").font(.system(size: 28, weight: .bold))
            if let m = d.bestPRMonth {
                Text("\(m.1) of them in \(m.0), your best month.").font(.system(size: 17)).opacity(0.8).padding(.top, 6)
            }
            if let top = d.jumps.first {
                Text("JANUARY → NOW").font(.system(size: 12, weight: .bold)).kerning(1).opacity(0.6).padding(.top, 40).padding(.bottom, 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text("BIGGEST JUMP").font(.system(size: 11, weight: .bold)).kerning(1)
                    HStack {
                        Text(top.name).font(.system(size: 22, weight: .bold))
                        Spacer()
                        Text("+\(Fmt.wu(top.delta.rounded()))").font(.system(size: 22, weight: .bold))
                    }
                    Text("\(Fmt.w(top.from.rounded())) → \(Fmt.wu(top.to.rounded())) est. 1RM").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.black).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.orange, in: RoundedRectangle(cornerRadius: 14))
                let rows = Array(d.jumps.dropFirst().prefix(d.bodyweightJump == nil ? 3 : 2)) + (d.bodyweightJump.map { [$0] } ?? [])
                ForEach(Array(rows.enumerated()), id: \.offset) { i, j in
                    HStack {
                        Text(j.name).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text("\(j.isReps ? "\(Int(j.from))" : Fmt.w(j.from.rounded())) → ").foregroundStyle(Color.white.opacity(0.7))
                            + Text(j.isReps ? "\(Int(j.to)) reps" : Fmt.wu(j.to.rounded())).bold()
                    }
                    .font(.system(size: 15)).padding(.vertical, 14)
                    if i < rows.count - 1 { Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5) }
                }
            }
        }
    }

    private func running(_ d: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if d.runCount > 0 {
                Text("You ran").font(.system(size: 22, weight: .bold))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.num(Units.runDisplay(d.runMeters).rounded(), maxDecimals: 0)).font(.system(size: 88, weight: .heavy)).minimumScaleFactor(0.5).lineLimit(1)
                    Text(Units.runLabel == "mi" ? "miles" : "km").font(.system(size: 26, weight: .bold))
                }
                Text("Across \(d.runCount) run\(d.runCount == 1 ? "" : "s").\(WrappedData.runFact(d.runMeters).map { " \($0)" } ?? "")")
                    .font(.system(size: 19)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You showed up").font(.system(size: 22, weight: .bold))
                Text("\(d.sessions)").font(.system(size: 88, weight: .heavy))
                Text("times to lift.").font(.system(size: 22, weight: .bold))
            }
            Text("HOW YOU SHOWED UP").font(.system(size: 12, weight: .bold)).kerning(1).padding(.top, 44).padding(.bottom, 10)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                tile(d.topWeekday ?? "–", "your most-trained day")
                tile(d.earliest.map(Fmt.time) ?? "–", "your earliest workout")
                tile("\(d.streakWeeks) week\(d.streakWeeks == 1 ? "" : "s")", "longest streak hitting your goal")
                tile(d.bestMonth ?? "–", "your most consistent month")
            }
        }
    }

    private func tile(_ v: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 24, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 13, weight: .medium)).lineLimit(2)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func headline(_ d: WrappedData) -> String {
        let lighter = (d.weightTo ?? 0) < (d.weightFrom ?? 0) - 1
        let heavier = (d.weightTo ?? 0) > (d.weightFrom ?? 0) + 1
        let stronger = !d.jumps.isEmpty
        switch (lighter, heavier, stronger) {
        case (true, _, true): return "Lighter and stronger."
        case (_, true, true): return "Bigger and stronger."
        case (_, _, true): return "Stronger."
        case (true, _, false): return "Lighter."
        default: return "That's your year."
        }
    }

    private func body(_ d: WrappedData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline(d)).font(.system(size: 40, weight: .heavy)).fixedSize(horizontal: false, vertical: true).padding(.top, -24)
            HStack(spacing: 10) {
                if let f = d.weightFrom, let t = d.weightTo {
                    stat("\(Fmt.signedW(t - f)) \(Units.unitLabel)", "\(Fmt.fixed(Units.display(f), 1)) → \(Fmt.fixed(Units.display(t), 1)) trend weight", Palette.cyan)
                }
                if let f = d.ratioFrom, let t = d.ratioTo {
                    stat(String(format: "%.2f×", t), String(format: "bench per bodyweight, %@ %.2f×", t >= f ? "up from" : "from", f), Palette.orange)
                }
            }
            if let a = d.firstPhoto, let b = d.lastPhoto {
                if photosVisible {
                    HStack(spacing: 10) {
                        photo(a)
                        photo(b)
                    }
                } else {
                    Button { Task { photosUnlocked = await PhotoStore.unlock() } } label: {
                        Label("Unlock progress photos", systemImage: "faceid").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.cyan)
                            .frame(maxWidth: .infinity).frame(height: 120).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                toggle("Include weight", $includeWeight)
                if photosVisible && d.firstPhoto != nil { toggle("Include photos", $includePhotos) }
            }
            .frame(maxWidth: .infinity)
            Button { share = ShareItem(image: shareImage(d)) } label: {
                Label("Share your year", systemImage: "square.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 50).background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            Button("Watch again") { page = 0 }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.orange)
                .frame(maxWidth: .infinity).padding(.bottom, 8)
        }
    }

    private func stat(_ v: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(.system(size: 26, weight: .heavy)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func photo(_ p: ProgressPhoto) -> some View {
        PhotoImage(photo: p).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                Text(Fmt.date(p.date, "MMMM")).font(.system(size: 13, weight: .bold)).padding(10)
            }
    }

    private func toggle(_ t: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            HStack(spacing: 5) {
                if on.wrappedValue { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                Text(t)
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(on.wrappedValue ? .black : .white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(on.wrappedValue ? Color.white : Palette.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Share

    private func shareImage(_ d: WrappedData) -> UIImage {
        let (n, suffix) = WrappedData.big(Units.display(d.volume))
        let card = VStack(alignment: .leading, spacing: 14) {
            Text("MY \(String(d.year)) IN TRAINING").font(.system(size: 13, weight: .bold)).kerning(1).foregroundStyle(Palette.orange)
            Text("\(n)\(suffix) \(Units.unitLabel) lifted").font(.system(size: 34, weight: .heavy))
            Text("\(d.sessions) sessions · \(d.prCount) PRs\(d.runCount > 0 ? " · \(Fmt.num(Units.runDisplay(d.runMeters).rounded(), maxDecimals: 0)) \(Units.runLabel) run" : "")")
                .font(.system(size: 17, weight: .semibold))
            if let j = d.jumps.first {
                Text("Biggest jump: \(j.name) +\(Fmt.wu(j.delta.rounded()))").font(.system(size: 15)).foregroundStyle(Palette.secondary)
            }
            if includeWeight, let f = d.weightFrom, let t = d.weightTo {
                Text("Trend weight \(Fmt.fixed(Units.display(f), 1)) → \(Fmt.fixed(Units.display(t), 1)) \(Units.unitLabel)").font(.system(size: 15)).foregroundStyle(Palette.cyan)
            }
            if includePhotos, photosVisible, let a = d.firstPhoto, let b = d.lastPhoto {
                HStack(spacing: 8) {
                    ForEach([a, b], id: \.uuid) { p in
                        Color(Palette.card).aspectRatio(3 / 4, contentMode: .fit)
                            .overlay { if let i = PhotoStore.image(p) { Image(uiImage: PhotoStore.blurFaces(i)).resizable().scaledToFill() } }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(24).frame(width: 400, alignment: .leading).background(Color.black).foregroundStyle(.white)
        let r = ImageRenderer(content: card)
        r.scale = 3
        return r.uiImage ?? UIImage()
    }
}
