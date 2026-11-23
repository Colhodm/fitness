import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Log an indoor run or walk from a photo of the treadmill console. Text is read on the phone with Vision.
struct TreadmillImportView: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var reading = false
    @State private var readSomething = false
    @State private var isWalk = false
    @State private var start = Date().addingTimeInterval(-1800)
    @State private var time = ""
    @State private var distance = ""
    @State private var km = AppSettings.shared.unit == .kg
    @State private var calories = ""
    @State private var saving = false
    @State private var error: String?

    private var seconds: Int? { TreadmillParser.clock(time) ?? Int(time).map { $0 * 60 } }
    private var meters: Double? {
        guard let d = Double(distance.replacingOccurrences(of: ",", with: ".")), d > 0 else { return nil }
        return km ? d * 1000 : d * Units.metersPerMile
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label(image == nil ? "Take photo of treadmill" : "Retake photo", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $item, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                    if reading { HStack { ProgressView(); Text("Reading the screen…").foregroundStyle(Palette.secondary) } }
                } footer: {
                    Text(reading ? "Reading time, distance and calories from the photo."
                         : image == nil ? "Snap the console at the end of your session. Time, distance and calories are read on this iPhone; check them before saving."
                         : readSomething ? "Check the numbers below. Fix anything the photo got wrong."
                         : "Couldn't read numbers from this photo. Type them in below, or try a straighter photo without glare.")
                }
                Section("Session") {
                    Picker("Type", selection: $isWalk) {
                        Text("Run").tag(false)
                        Text("Walk").tag(true)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Started", selection: $start, in: ...Date())
                    LabeledContent("Time") {
                        TextField("mm:ss", text: $time).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Distance") {
                        HStack {
                            TextField("0.00", text: $distance).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Picker("", selection: $km) { Text("mi").tag(false); Text("km").tag(true) }
                                .pickerStyle(.segmented).frame(width: 96)
                        }
                    }
                    LabeledContent("Calories") {
                        TextField("optional", text: $calories).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    if let s = seconds, let m = meters, s > 0 {
                        let per = km ? m / 1000 : m / Units.metersPerMile
                        LabeledContent("Pace", value: "\(Fmt.clock(Int((Double(s) / per).rounded()))) /\(km ? "km" : "mi")")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Treadmill session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving || (seconds ?? 0) <= 0 || meters == nil)
                }
            }
            .onChange(of: item) { _, new in
                guard let new else { return }
                Task {
                    if let data = try? await new.loadTransferable(type: Data.self), let img = UIImage(data: data) { await use(img) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in Task { await use(img) } }.ignoresSafeArea()
            }
        }
    }

    private func use(_ img: UIImage) async {
        image = img
        reading = true
        let r = TreadmillParser.parse(await TreadmillOCR.recognize(img))
        reading = false
        readSomething = r.seconds != nil || r.distance != nil || r.calories != nil
        if let s = r.seconds {
            time = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
            start = Date().addingTimeInterval(-Double(s))
        }
        if let d = r.distance { distance = Fmt.num(d, maxDecimals: 2) }
        if let k = r.distanceIsKm { km = k }
        if let c = r.calories { calories = "\(c)" }
        isWalk = TreadmillParser.looksLikeWalk(r)
    }

    private func save() {
        guard let s = seconds, let m = meters else { return }
        saving = true
        error = nil
        Task {
            let ok = await health.saveCardio(walk: isWalk, start: start, duration: Double(s), meters: m, kcal: Double(calories) ?? 0)
            saving = false
            if ok { dismiss() } else { error = "Couldn't save to Apple Health. In Settings › Health › Data Access & Devices › Lift + Run + Body, turn on writing Workouts, Walking + Running Distance and Active Energy." }
        }
    }
}

enum TreadmillOCR {
    static func recognize(_ image: UIImage) async -> [TreadmillParser.Item] {
        let maxSide: CGFloat = 2200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        guard let cg = UIGraphicsImageRenderer(size: size, format: format).image(actions: { _ in image.draw(in: CGRect(origin: .zero, size: size)) }).cgImage
        else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            return (request.results ?? []).compactMap { obs in
                obs.topCandidates(1).first.map { TreadmillParser.Item(text: $0.string, box: obs.boundingBox) }
            }
        }.value
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
