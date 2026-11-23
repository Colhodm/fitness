import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Grid

struct ProgressPhotosView: View {
    @EnvironmentObject var router: Router
    @Environment(\.modelContext) private var context
    @ObservedObject private var settings = AppSettings.shared
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var pose: PhotoPose = .front
    @State private var unlocked = false
    @State private var capturing = false
    @State private var viewing: ProgressPhoto?

    private var locked: Bool { settings.photoLock && !unlocked }

    var body: some View {
        let shown = photos.filter { $0.pose == pose }
        Screen {
            VStack(alignment: .leading, spacing: 4) {
                Text("Progress photos").font(.system(size: 34, weight: .bold))
                Label((settings.photoBackup ? "On this iPhone · in iCloud backup" : "Only on this iPhone") + (settings.photoLock ? " · locked with Face ID" : ""),
                      systemImage: settings.photoLock ? "lock" : "iphone")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            if locked {
                NoticeCard(icon: "faceid", tint: Palette.cyan, title: "Photos are locked", message: PhotoStore.canAuthenticate ? "Unlock with Face ID to see your progress photos." : "Set a passcode on this iPhone to unlock, or turn the lock off in Settings.",
                           actionTitle: "Unlock") { Task { unlocked = await PhotoStore.unlock() } }
            } else {
                SegmentedPicker(options: PhotoPose.allCases.map { ($0, $0.title) }, selection: $pose)
                if shown.isEmpty {
                    NoticeCard(icon: "camera", tint: Palette.cyan, title: "No \(pose.rawValue) photos yet",
                               message: "Take front, side and back photos in the same spot and light. They stay in this app, not your Photos library.")
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                        ForEach(shown) { p in
                            Button { viewing = p } label: { PhotoCell(photo: p) }.buttonStyle(.plain)
                        }
                    }
                }
                dueCard
            }
        }
        .toolbar {
            if !locked && photos.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Compare") { router.push(.photoCompare(pose.rawValue)) }.tint(Palette.cyan)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { if settings.photoLock && !unlocked { unlocked = await PhotoStore.unlock() } }
        .fullScreenCover(isPresented: $capturing) { PhotoCaptureView(startPose: .front) }
        .sheet(item: $viewing) { PhotoDetailSheet(photo: $0) }
    }

    private var dueCard: some View {
        let last = photos.first?.date
        let due = PhotoStore.nextDue(after: last)
        let days = due.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: $0)).day ?? 0 }
        let title: String = {
            guard last != nil else { return "Take your first set" }
            guard let days else { return "Reminders are off" }
            return days > 1 ? "Next photo due in \(days) days" : (days == 1 ? "Next photo due tomorrow" : "Photo day")
        }()
        let w = settings.photoReminderWeeks
        let sub = w == 0 ? "Turn reminders on in Settings · 3 poses" : "Every \(w == 1 ? "week" : "\(w) weeks"), \(reminderTimeLabel) · 3 poses"
        return Card(padding: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(sub).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button { capturing = true } label: {
                    Text("Take now").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 16).frame(height: 36).background(Palette.cyan, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reminderTimeLabel: String {
        let m = settings.photoReminderMinutes
        return m < 12 * 60 ? "mornings" : (m < 17 * 60 ? "afternoons" : "evenings")
    }
}

struct PhotoCell: View {
    let photo: ProgressPhoto
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PhotoImage(photo: photo).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Text(Fmt.date(photo.date, "MMM d")).font(.system(size: 12, weight: .semibold))
                Spacer()
                if photo.weight > 0 { Text(Fmt.fixed(Units.display(photo.weight), 1)).font(.system(size: 12)).foregroundStyle(Palette.secondary).monospacedDigit() }
            }
        }
    }
}

struct PhotoImage: View {
    let photo: ProgressPhoto?
    var body: some View {
        Color(Palette.card).overlay {
            if let photo, let img = PhotoStore.image(photo) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(Palette.fieldHigh)
            }
        }
        .clipped()
    }
}

struct PhotoDetailSheet: View {
    let photo: ProgressPhoto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PhotoImage(photo: photo).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                    Card {
                        StampRow(label: "Weight", value: photo.weight > 0 ? Fmt.wu(photo.weight) : "–")
                        StampRow(label: "Body fat", value: photo.bodyFat > 0 ? "\(Fmt.fixed(photo.bodyFat * 100, 1))%" : "–")
                        StampRow(label: "Lean mass", value: photo.leanMass > 0 ? Fmt.wu(photo.leanMass) : "–")
                        StampRow(label: "Bench est. 1RM", value: photo.bench1RM > 0 ? Fmt.wu(photo.bench1RM.rounded()) : "–")
                        StampRow(label: "Squat est. 1RM", value: photo.squat1RM > 0 ? Fmt.wu(photo.squat1RM.rounded()) : "–")
                    }
                }
                .padding(16)
            }
            .background(Color.black)
            .navigationTitle("\(photo.pose.title) · \(Fmt.date(photo.date, "MMM d, yyyy"))").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Delete", role: .destructive) { confirming = true }.tint(.red) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(Palette.cyan) }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) { PhotoStore.delete(photo, context: context); dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct StampRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(Palette.secondary).monospacedDigit() }
            .font(.system(size: 15)).padding(.vertical, 6)
    }
}

// MARK: - Camera

final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum State { case starting, ready, unavailable }
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "progress-camera")
    @Published var state: State = .starting
    @Published var position: AVCaptureDevice.Position = .back
    private var completion: ((UIImage?) -> Void)?

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { ok in
                if ok { self.queue.async { self.configure(); self.session.startRunning() } } else { self.set(.unavailable) }
            }
        } else if status == .authorized {
            queue.async { self.configure(); self.session.startRunning() }
        } else {
            set(.unavailable)
        }
    }

    private func set(_ s: State) { DispatchQueue.main.async { self.state = s } }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        let pos = position
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            set(.unavailable)
            return
        }
        session.addInput(input)
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        set(.ready)
    }

    func flip() {
        position = position == .back ? .front : .back
        queue.async { self.configure() }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        completion = done
        queue.async {
            if let c = self.output.connection(with: .video) { c.isVideoMirrored = self.position == .front }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let img = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async { self.completion?(img); self.completion = nil }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct PhotoCaptureView: View {
    let startPose: PhotoPose
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @StateObject private var camera = CameraModel()
    @State private var pose: PhotoPose = .front
    @State private var showOutline = true
    @State private var outline: UIImage?
    @State private var timer = 0
    @State private var countdown = 0
    @State private var takenThisSession: Set<PhotoPose> = []
    @State private var picked: PhotosPickerItem?
    @State private var flash = false
    @State private var countdownTask: Task<Void, Never>?
    @State private var saveFailed = false

    private var last: ProgressPhoto? { photos.first { $0.pose == pose } }
    private var index: Int { PhotoPose.allCases.firstIndex(of: pose)! }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(Palette.card)
                if camera.state == .ready { CameraPreview(session: camera.session) }
                if camera.state == .unavailable {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.system(size: 32)).foregroundStyle(Palette.secondary)
                        Text("Camera isn't available. Allow camera access in Settings, or choose a photo you already took.")
                            .font(.system(size: 15)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                        PhotosPicker(selection: $picked, matching: .images) {
                            Text("Choose photo").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                                .padding(.horizontal, 18).frame(height: 38).background(Palette.cyan, in: Capsule())
                        }
                    }
                }
                if showOutline { guide }
                if countdown > 0 {
                    Text("\(countdown)").font(.system(size: 96, weight: .bold)).foregroundStyle(.white).shadow(radius: 8)
                }
                if flash { Color.white.opacity(0.7) }
            }
            .clipped()
            .overlay(alignment: .top) { topBar }
            controls
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { pose = startPose; camera.start() }
        .onDisappear { countdownTask?.cancel(); camera.stop() }
        .alert("Couldn't save the photo", isPresented: $saveFailed) { Button("OK", role: .cancel) {} } message: { Text("Try taking it again.") }
        .task(id: pose) { outline = nil; if let last { outline = await PhotoStore.outline(last) } }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { saved(img) }
                picked = nil
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(.black.opacity(0.6), in: Circle())
                }
                Spacer()
                Text("\(pose.title) · \(index + 1) of 3").font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 32).background(.black.opacity(0.6), in: Capsule())
                Spacer()
                Button { showOutline.toggle() } label: {
                    Label("Outline", systemImage: showOutline ? "circle.dashed" : "circle.slash")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(showOutline ? Palette.cyan : .white)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background((showOutline ? Palette.cyan.opacity(0.25) : Color.black.opacity(0.6)), in: Capsule())
                }
            }
            if let last, showOutline {
                Text("Match the outline from \(Fmt.date(last.date, "MMM d")) · same spot, morning light")
                    .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var guide: some View {
        GeometryReader { g in
            ZStack {
                if let outline {
                    Image(uiImage: outline).resizable().renderingMode(.template).scaledToFill()
                        .foregroundStyle(Palette.cyan.opacity(0.8)).frame(width: g.size.width, height: g.size.height).clipped()
                } else if let last, let img = PhotoStore.image(last) {
                    Image(uiImage: img).resizable().scaledToFill().opacity(0.25).frame(width: g.size.width, height: g.size.height).clipped()
                } else {
                    let w = g.size.width, h = g.size.height
                    Circle().stroke(Palette.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .frame(width: w * 0.22, height: w * 0.22).position(x: w / 2, y: h * 0.2)
                    UnevenRoundedRectangle(topLeadingRadius: w * 0.25, topTrailingRadius: w * 0.25)
                        .stroke(Palette.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .frame(width: w * 0.5, height: h * 0.6).position(x: w / 2, y: h * 0.6)
                }
                guideLine("Top of head", y: g.size.height * 0.17, width: g.size.width)
                guideLine("Feet", y: g.size.height * 0.92, width: g.size.width)
            }
        }
        .allowsHitTesting(false)
    }

    private func guideLine(_ t: String, y: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white.opacity(0.35)).frame(width: width - 32, height: 1)
            Text(t).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).offset(y: 5)
        }
        .position(x: width / 2, y: y + 8)
    }

    private var controls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 24) {
                ForEach(PhotoPose.allCases) { p in
                    Button { pose = p } label: {
                        Text(p.rawValue.uppercased()).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(p == pose ? Palette.cyan : (takenThisSession.contains(p) ? Palette.secondary : .white))
                    }
                }
            }
            HStack {
                Button { camera.flip() } label: {
                    PhotoImage(photo: last).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .bold))
                                .padding(4).background(.black.opacity(0.7), in: Circle())
                        }
                }
                .disabled(camera.state != .ready)
                Spacer()
                Button(action: shoot) {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                        .overlay(Circle().fill(.white).padding(7))
                }
                .disabled(camera.state != .ready || countdown > 0)
                .opacity(camera.state == .ready ? 1 : 0.4)
                Spacer()
                Button { timer = timer == 0 ? 3 : (timer == 3 ? 10 : 0) } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "timer").font(.system(size: 15, weight: .semibold))
                        Text(timer == 0 ? "Off" : "\(timer)s").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white).frame(width: 48, height: 48).background(Palette.field, in: Circle())
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 18).padding(.bottom, 12)
    }

    private func shoot() {
        guard timer > 0 else { take(); return }
        countdown = timer
        countdownTask = Task {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { countdown = 0; return }
                countdown -= 1
            }
            take()
        }
    }

    private func take() {
        guard camera.state == .ready, camera.session.isRunning else { return }
        flash = true
        withAnimation(.easeOut(duration: 0.3)) { flash = false }
        camera.capture { img in if let img { saved(img) } }
    }

    private func saved(_ img: UIImage) {
        guard PhotoStore.save(img, pose: pose, context: context) != nil else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            saveFailed = true
            return
        }
        PhotoStore.scheduleReminder(context: context)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        takenThisSession.insert(pose)
        if let next = PhotoPose.allCases.first(where: { !takenThisSession.contains($0) }) { pose = next } else { dismiss() }
    }
}

// MARK: - Compare

struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct PhotoCompareView: View {
    let pose: PhotoPose
    @ObservedObject private var settings = AppSettings.shared
    @Query(sort: \ProgressPhoto.date) private var all: [ProgressPhoto]
    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var mode = 0
    @State private var slider: CGFloat = 0.5
    @State private var frame = 0
    @State private var blurFaces = true
    @State private var addNumbers = false
    @State private var share: ShareItem?
    @State private var unlocked = false

    private var photos: [ProgressPhoto] { all.filter { $0.pose == pose } }
    private var before: ProgressPhoto? { photos.first { $0.uuid == beforeID } ?? photos.first }
    private var after: ProgressPhoto? { photos.first { $0.uuid == afterID } ?? photos.last }

    var body: some View {
        Screen {
            if settings.photoLock && !unlocked {
                NoticeCard(icon: "faceid", tint: Palette.cyan, title: "Photos are locked", message: PhotoStore.canAuthenticate ? "Unlock with Face ID to compare." : "Set a passcode on this iPhone to unlock, or turn the lock off in Settings.",
                           actionTitle: "Unlock") { Task { unlocked = await PhotoStore.unlock() } }
            } else if let before, let after, photos.count >= 2 {
                header(before, after)
                SegmentedPicker(options: [(0, "Side by side"), (1, "Slider"), (2, "Timelapse")], selection: $mode)
                switch mode {
                case 0: sideBySide(before, after)
                case 1: sliderView(before, after)
                default: timelapse
                }
                table(before, after)
                Card(padding: 14) {
                    Toggle(isOn: $blurFaces) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blur face when sharing").font(.system(size: 15, weight: .semibold))
                            Text("If no face is found, the top of the photo is blurred. Numbers are left off shared images unless you add them").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                    }
                    .tint(Palette.cyan)
                    RowDivider().padding(.vertical, 10)
                    Toggle("Add numbers", isOn: $addNumbers).font(.system(size: 15, weight: .semibold)).tint(Palette.cyan)
                }
            } else {
                NoticeCard(icon: "photo.on.rectangle", tint: Palette.cyan, title: "Need two \(pose.rawValue) photos",
                           message: "Take another \(pose.rawValue) photo to compare.")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let before, let after, photos.count >= 2, !(settings.photoLock && !unlocked) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { share = ShareItem(image: shareImage(before, after)) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .tint(Palette.cyan)
                }
            }
        }
        .task { if settings.photoLock && !unlocked { unlocked = await PhotoStore.unlock() } }
        .sheet(item: $share) { ShareSheet(items: [$0.image]) }
    }

    private func header(_ b: ProgressPhoto, _ a: ProgressPhoto) -> some View {
        let days = Calendar.current.dateComponents([.day], from: b.date, to: a.date).day ?? 0
        let apart = days >= 14 ? "\(Int((Double(days) / 7).rounded())) weeks apart" : "\(days) day\(days == 1 ? "" : "s") apart"
        var parts: [String] = []
        if b.weight > 0, a.weight > 0, abs(a.weight - b.weight) >= 0.1 {
            parts.append("\(Fmt.w(abs(a.weight - b.weight))) \(Units.unitLabel) \(a.weight < b.weight ? "lighter" : "heavier")")
        }
        let lifts = [(b.bench1RM, a.bench1RM), (b.squat1RM, a.squat1RM)].filter { $0.0 > 0 && $0.1 > 0 }
        if !lifts.isEmpty && lifts.allSatisfy({ $0.1 > $0.0 }) { parts.append("stronger on every main lift") }
        return VStack(alignment: .leading, spacing: 4) {
            Text(apart).font(.system(size: 28, weight: .bold))
            if !parts.isEmpty { Text(parts.joined(separator: " and ")).font(.system(size: 15)).foregroundStyle(Palette.secondary) }
        }
    }

    private func dateMenu(_ selected: ProgressPhoto, set: @escaping (UUID) -> Void) -> some View {
        Menu {
            ForEach(photos.reversed()) { p in Button(Fmt.date(p.date, "MMM d, yyyy")) { set(p.uuid) } }
        } label: {
            HStack(spacing: 3) {
                Text(Fmt.date(selected.date, "MMM d"))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 28).background(.black.opacity(0.7), in: Capsule())
        }
        .padding(8)
    }

    private func sideBySide(_ b: ProgressPhoto, _ a: ProgressPhoto) -> some View {
        HStack(spacing: 8) {
            PhotoImage(photo: b).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) { dateMenu(b) { beforeID = $0 } }
            PhotoImage(photo: a).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) { dateMenu(a) { afterID = $0 } }
        }
    }

    private func sliderView(_ b: ProgressPhoto, _ a: ProgressPhoto) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                PhotoImage(photo: a)
                PhotoImage(photo: b).mask(alignment: .leading) { Rectangle().frame(width: g.size.width * slider) }
                Rectangle().fill(.white).frame(width: 2).offset(x: g.size.width * slider - 1)
                Circle().fill(.white).frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.black))
                    .offset(x: g.size.width * slider - 15)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { slider = min(1, max(0, $0.location.x / g.size.width)) })
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topLeading) { dateMenu(b) { beforeID = $0 } }
        .overlay(alignment: .topTrailing) { dateMenu(a) { afterID = $0 } }
    }

    private var timelapse: some View {
        let list = photos
        let p = list.isEmpty ? nil : list[frame % list.count]
        return PhotoImage(photo: p).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                if let p {
                    Text(Fmt.date(p.date, "MMM d, yyyy")).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 28).background(.black.opacity(0.7), in: Capsule()).padding(8)
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(450))
                    frame += 1
                }
            }
    }

    private func table(_ b: ProgressPhoto, _ a: ProgressPhoto) -> some View {
        let rows: [(String, Double, Double, (Double) -> String, Bool)] = [
            ("Weight", b.weight, a.weight, { Fmt.fixed(Units.display($0), 1) }, false),
            ("Body fat", b.bodyFat * 100, a.bodyFat * 100, { "\(Fmt.fixed($0, 1))%" }, false),
            ("Lean mass", b.leanMass, a.leanMass, { Fmt.fixed(Units.display($0), 1) }, false),
            ("Bench 1RM", b.bench1RM, a.bench1RM, { Fmt.w($0.rounded()) }, true),
            ("Squat 1RM", b.squat1RM, a.squat1RM, { Fmt.w($0.rounded()) }, true),
        ].filter { $0.1 > 0 && $0.2 > 0 }
        return Card(padding: 0) {
            HStack {
                Text("ON THE DAY").frame(maxWidth: .infinity, alignment: .leading)
                Text(Fmt.date(b.date, "MMM d").uppercased()).frame(width: 64, alignment: .trailing)
                Text(Fmt.date(a.date, "MMM d").uppercased()).frame(width: 64, alignment: .trailing)
                Text("CHANGE").frame(width: 70, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary).padding(.horizontal, 14).padding(.vertical, 10)
            if rows.isEmpty {
                Text("No weigh-ins or lifts on these days.").font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(14)
            }
            ForEach(rows, id: \.0) { r in
                RowDivider(inset: 14)
                let isPercent = r.0 == "Body fat"
                let delta = r.4 || isPercent ? r.2 - r.1 : Units.display(r.2) - Units.display(r.1)
                HStack {
                    Text(r.0).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.3(r.1)).foregroundStyle(Palette.secondary).frame(width: 64, alignment: .trailing)
                    Text(r.3(r.2)).fontWeight(.semibold).frame(width: 64, alignment: .trailing)
                    Text(isPercent ? Fmt.signed(delta) : "\(r.4 ? Fmt.signedW(delta) : Fmt.signed(delta)) \(Units.unitLabel)")
                        .foregroundStyle(r.4 ? Palette.orange : Palette.cyan).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 15)).monospacedDigit().padding(.horizontal, 14).frame(height: 40)
            }
        }
    }

    private func shareImage(_ b: ProgressPhoto, _ a: ProgressPhoto) -> UIImage {
        func img(_ p: ProgressPhoto) -> UIImage? { PhotoStore.image(p).map { blurFaces ? PhotoStore.blurFaces($0) : $0 } }
        let (bi, ai) = (img(b), img(a))
        let card = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach([(b, bi), (a, ai)], id: \.0.uuid) { p, i in
                    VStack(alignment: .leading, spacing: 4) {
                        Color(Palette.card).aspectRatio(3 / 4, contentMode: .fit)
                            .overlay { if let i { Image(uiImage: i).resizable().scaledToFill() } }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        HStack {
                            Text(Fmt.date(p.date, "MMM d, yyyy")).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if addNumbers && p.weight > 0 { Text(Fmt.wu(p.weight)).font(.system(size: 13)).foregroundStyle(Palette.secondary) }
                        }
                    }
                }
            }
            if addNumbers, b.bench1RM > 0, a.bench1RM > 0 {
                Text("Bench \(Fmt.w(b.bench1RM.rounded())) → \(Fmt.wu(a.bench1RM.rounded())) · Squat \(Fmt.w(b.squat1RM.rounded())) → \(Fmt.wu(a.squat1RM.rounded()))")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
        }
        .padding(16).frame(width: 400).background(Color.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: card)
        r.scale = 3
        return r.uiImage ?? UIImage()
    }
}
