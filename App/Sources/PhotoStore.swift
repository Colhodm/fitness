import CoreImage
import Foundation
import LocalAuthentication
import SwiftData
import UIKit
import UserNotifications
import Vision

/// Progress photo files. They live in the app's Application Support folder (never the Photos library),
/// excluded from iCloud backup unless the user turns backup on.
@MainActor
enum PhotoStore {
    private static let cache = NSCache<NSString, UIImage>()
    private static var outlines: [String: UIImage] = [:]

    static var directory: URL {
        var base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleData") { base = FileManager.default.temporaryDirectory }
        #endif
        var dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = !AppSettings.shared.photoBackup
        try? dir.setResourceValues(values)
        return dir
    }

    static func applyBackupSetting() { _ = directory }

    static func image(_ p: ProgressPhoto) -> UIImage? {
        if let img = cache.object(forKey: p.fileName as NSString) { return img }
        guard let img = UIImage(contentsOfFile: directory.appendingPathComponent(p.fileName).path) else { return nil }
        cache.setObject(img, forKey: p.fileName as NSString)
        return img
    }

    @discardableResult
    static func save(_ image: UIImage, pose: PhotoPose, date: Date = Date(), context: ModelContext) -> ProgressPhoto? {
        let img = normalized(image)
        let name = "\(UUID().uuidString).jpg"
        guard let data = img.jpegData(compressionQuality: 0.85),
              (try? data.write(to: directory.appendingPathComponent(name), options: .completeFileProtection)) != nil else { return nil }
        cache.setObject(img, forKey: name as NSString)
        let p = ProgressPhoto(date: date, pose: pose, fileName: name)
        stamp(p, context: context)
        context.insert(p)
        try? context.save()
        return p
    }

    static func delete(_ p: ProgressPhoto, context: ModelContext) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(p.fileName))
        cache.removeObject(forKey: p.fileName as NSString)
        context.delete(p)
        try? context.save()
    }

    /// That day's weigh-in, body fat and lean mass, plus the bench and squat est. 1RM at the time.
    static func stamp(_ p: ProgressPhoto, context: ModelContext) {
        let h = HealthStore.shared
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: p.date).addingTimeInterval(86400)
        func recent(_ s: [BodySample], days: Double) -> Double? {
            s.filter { $0.date < cutoff && $0.date >= cutoff.addingTimeInterval(-days * 86400) }.last?.value
        }
        p.weight = h.weights.first { cal.isDate($0.date, inSameDayAs: p.date) }?.value
            ?? BodyMath.trend(at: p.date, BodyMath.trend(h.weights.filter { $0.date < cutoff })) ?? 0
        p.bodyFat = recent(h.bodyFat, days: 7) ?? 0
        p.leanMass = recent(h.lean, days: 7) ?? 0
        func e1RM(_ name: String) -> Double {
            guard let ex = Library.exercise(named: name, in: context) else { return 0 }
            return Analytics.sessions(ex, before: cutoff).suffix(3).map(\.bestE1RM).max() ?? 0
        }
        p.bench1RM = e1RM("Bench Press")
        p.squat1RM = e1RM("Back Squat")
    }

    private static func normalized(_ image: UIImage, maxSide: CGFloat = 1800) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: Outline and face blur

    /// The person's outline from a photo (Vision person segmentation), as an alpha mask.
    static func outline(_ p: ProgressPhoto) async -> UIImage? {
        if let o = outlines[p.fileName] { return o }
        guard let img = image(p), let cg = img.cgImage else { return nil }
        let result = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let req = VNGeneratePersonSegmentationRequest()
            req.qualityLevel = .balanced
            req.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try? VNImageRequestHandler(cgImage: cg).perform([req])
            guard let buf = req.results?.first?.pixelBuffer else { return nil }
            let mask = CIImage(cvPixelBuffer: buf)
            let scaled = mask.transformed(by: CGAffineTransform(scaleX: CGFloat(cg.width) / mask.extent.width, y: CGFloat(cg.height) / mask.extent.height))
            let edge = scaled.applyingFilter("CIMorphologyGradient", parameters: ["inputRadius": 3]).applyingFilter("CIMaskToAlpha")
            return CIContext().createCGImage(edge, from: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }.value
        guard let result else { return nil }
        let out = UIImage(cgImage: result)
        outlines[p.fileName] = out
        return out
    }

    nonisolated static func blurFaces(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let req = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let ci = CIImage(cgImage: cg)
        var rects = (req.results ?? []).map { f -> CGRect in
            let r = VNImageRectForNormalizedRect(f.boundingBox, cg.width, cg.height)
            return r.insetBy(dx: -r.width * 0.3, dy: -r.height * 0.4)
        }
        // No face found: blur the top of the frame, where the head is in a progress photo.
        if rects.isEmpty { rects = [CGRect(x: 0, y: ci.extent.height * 0.68, width: ci.extent.width, height: ci.extent.height * 0.32)] }
        let blurred = ci.clampedToExtent()
            .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(ci.extent.width, ci.extent.height) / 24])
            .cropped(to: ci.extent)
        var out = ci
        for r in rects { out = blurred.cropped(to: r).composited(over: out) }
        guard let result = CIContext().createCGImage(out, from: ci.extent) else { return UIImage() }
        return UIImage(cgImage: result)
    }

    // MARK: Lock and reminders

    static var canAuthenticate: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    /// Fails when the device has no passcode, so the lock never opens without authenticating.
    static func unlock() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your progress photos")) ?? false
    }

    static let reminderID = "progress-photo-reminder"

    static func nextDue(after last: Date?) -> Date? {
        let s = AppSettings.shared
        guard s.photoReminderWeeks > 0 else { return nil }
        let cal = Calendar.current
        let base = last.map { cal.date(byAdding: .day, value: 7 * s.photoReminderWeeks, to: $0)! } ?? Date()
        return cal.startOfDay(for: base).addingTimeInterval(Double(s.photoReminderMinutes) * 60)
    }

    static func scheduleReminder(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        var d = FetchDescriptor<ProgressPhoto>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        guard let last = (try? context.fetch(d))?.first, var due = nextDue(after: last.date) else { return }
        if due < Date() { due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!.addingTimeInterval(Double(AppSettings.shared.photoReminderMinutes) * 60) }
        let content = UNMutableNotificationContent()
        content.title = "Progress photo day"
        content.body = "Same spot, same light: front, side and back."
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    #if DEBUG
    /// Silhouette placeholders for Simulator screenshots.
    static func seedSamples(_ context: ModelContext, now: Date = Date()) {
        guard ((try? context.fetchCount(FetchDescriptor<ProgressPhoto>())) ?? 0) == 0 else { return }
        let cal = Calendar.current
        for i in 0..<6 {
            let day = cal.date(byAdding: .day, value: -6 - 14 * i, to: cal.startOfDay(for: now))!.addingTimeInterval(7.5 * 3600)
            for pose in PhotoPose.allCases {
                let img = silhouette(width: 0.42 + 0.012 * Double(i), side: pose == .side)
                save(img, pose: pose, date: day, context: context)
            }
        }
    }

    private static func silhouette(width: Double, side: Bool) -> UIImage {
        let size = CGSize(width: 600, height: 800)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.17, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.33, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 250, y: 150, width: 100, height: 100))
            let w = size.width * (side ? width * 0.7 : width)
            let body = UIBezierPath(roundedRect: CGRect(x: (size.width - w) / 2, y: 280, width: w, height: 600), byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: w / 2, height: w / 2))
            body.fill()
        }
    }
    #endif
}
