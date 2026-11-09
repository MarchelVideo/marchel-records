import SwiftUI
import AppKit
import AVFoundation

struct Recording: Identifiable, Hashable {
    let url: URL
    let date: Date
    let duration: Double
    var id: String { url.path }
}

@MainActor
final class AppState: ObservableObject {
    // live state
    @Published var isRecording = false
    @Published var busy = false
    @Published var elapsed: Double = 0
    @Published var levelL: Double = 0     // 0...1 needle position
    @Published var levelR: Double = 0
    @Published var dbL: Double = -60
    @Published var dbR: Double = -60
    @Published var status = ""
    @Published var apps: [AppItem] = []
    @Published var recents: [Recording] = []
    @Published var playingURL: URL?

    // settings (persisted)
    @Published var sourceID: String? { didSet { defaults.set(sourceID, forKey: "sourceID") } }
    @Published var sourceName: String { didSet { defaults.set(sourceName, forKey: "sourceName") } }
    @Published var format: AudioFormat { didSet { defaults.set(format.rawValue, forKey: "format") } }
    @Published var folder: URL { didSet { defaults.set(folder.path, forKey: "folder") } }
    @Published var trimSilence: Bool { didSet { defaults.set(trimSilence, forKey: "trim") } }

    private let defaults = UserDefaults.standard
    private let recorder = Recorder()
    private var timer: Timer?
    private var startDate: Date?
    private var player: AVAudioPlayer?
    private var hotKey: HotKey?

    init() {
        sourceID = defaults.string(forKey: "sourceID")
        sourceName = defaults.string(forKey: "sourceName") ?? "Вся система"
        format = AudioFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .wav
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        if let p = defaults.string(forKey: "folder"), FileManager.default.fileExists(atPath: p) {
            folder = URL(fileURLWithPath: p)
        } else {
            folder = desktop
        }
        trimSilence = defaults.object(forKey: "trim") as? Bool ?? true
        loadRecents()

        recorder.onLevels = { [weak self] l, r in
            Task { @MainActor in self?.updateLevels(l, r) }
        }
        recorder.onError = { [weak self] msg in
            Task { @MainActor in self?.status = msg }
        }
        HotKey.action = { [weak self] in self?.toggle() }
        hotKey = HotKey()
    }

    // MARK: recording
    func toggle() {
        Task { @MainActor in
            if isRecording { await stop() } else { await start() }
        }
    }

    func start() async {
        guard !busy, !isRecording else { return }
        busy = true
        defer { busy = false }
        stopPlayback()
        do {
            try await recorder.start(appBundleID: sourceID)
            isRecording = true
            startDate = Date()
            elapsed = 0
            status = ""
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let s = self.startDate else { return }
                    self.elapsed = Date().timeIntervalSince(s)
                    self.decayLevels()
                }
            }
        } catch {
            status = "Нет доступа к записи звука. Включите Marchel Records в Настройках → Конфиденциальность и безопасность → Запись экрана и системного звука, затем перезапустите приложение."
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func stop() async {
        guard isRecording else { return }
        busy = true
        defer { busy = false }
        timer?.invalidate()
        timer = nil
        let tmp = await recorder.stop()
        isRecording = false
        levelL = 0; levelR = 0; dbL = -60; dbR = -60
        guard let tmp else {
            status = "Звука не было — файл не создан"
            return
        }
        status = "Сохраняю…"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let date = startDate ?? Date()
        let base = "Marchel Records \(df.string(from: date))"
        let dst = uniqueURL(folder.appendingPathComponent(base).appendingPathExtension(format.ext))
        let fmt = format
        let trim = trimSilence
        do {
            let dur = try await Task.detached(priority: .userInitiated) {
                try AudioExport.export(from: tmp, to: dst, format: fmt, trim: trim)
            }.value
            try? FileManager.default.removeItem(at: tmp)
            if let dur {
                recents.insert(Recording(url: dst, date: date, duration: dur), at: 0)
                if recents.count > 30 { recents.removeLast(recents.count - 30) }
                saveRecents()
                status = "Сохранено: \(dst.lastPathComponent)"
            } else {
                status = "Была только тишина — файл не создан"
            }
        } catch {
            status = "Ошибка сохранения: \(error.localizedDescription)"
        }
    }

    private func uniqueURL(_ url: URL) -> URL {
        var u = url
        var i = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) (\(i))")
                .appendingPathExtension(url.pathExtension)
            i += 1
        }
        return u
    }

    // MARK: levels (VU ballistics)
    private func toNeedle(_ db: Double) -> Double { min(1, max(0, (db + 20) / 23)) }  // −20 … +3 dB

    private func updateLevels(_ l: Float, _ r: Float) {
        guard isRecording else { return }
        let dl = 20 * log10(max(Double(l), 0.000_01))
        let dr = 20 * log10(max(Double(r), 0.000_01))
        dbL = dl; dbR = dr
        let tl = toNeedle(dl), tr = toNeedle(dr)
        levelL = tl > levelL ? levelL + (tl - levelL) * 0.5 : levelL + (tl - levelL) * 0.12
        levelR = tr > levelR ? levelR + (tr - levelR) * 0.5 : levelR + (tr - levelR) * 0.12
    }

    private func decayLevels() {
        levelL *= 0.97
        levelR *= 0.97
    }

    // MARK: sources
    func refreshApps() async {
        if let list = try? await Recorder.runningApps() { apps = list }
    }

    func selectSource(_ app: AppItem?) {
        sourceID = app?.id
        sourceName = app?.name ?? "Вся система"
    }

    // MARK: folder
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Выбрать"
        panel.directoryURL = folder
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let u = panel.url { folder = u }
    }

    func openFolder() { NSWorkspace.shared.open(folder) }

    // MARK: recents
    func reveal(_ r: Recording) { NSWorkspace.shared.activateFileViewerSelecting([r.url]) }

    func togglePlay(_ r: Recording) {
        if playingURL == r.url { stopPlayback(); return }
        stopPlayback()
        guard let p = try? AVAudioPlayer(contentsOf: r.url) else {
            status = "Файл не найден"
            recents.removeAll { $0.url == r.url }
            saveRecents()
            return
        }
        player = p
        p.play()
        playingURL = r.url
        let url = r.url
        DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.1) { [weak self] in
            if self?.playingURL == url { self?.stopPlayback() }
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    private func loadRecents() {
        guard let arr = defaults.array(forKey: "recents") as? [[String: Any]] else { return }
        recents = arr.compactMap { d in
            guard let p = d["path"] as? String, FileManager.default.fileExists(atPath: p),
                  let t = d["date"] as? Double, let dur = d["dur"] as? Double else { return nil }
            return Recording(url: URL(fileURLWithPath: p), date: Date(timeIntervalSince1970: t), duration: dur)
        }
    }

    private func saveRecents() {
        defaults.set(recents.map { ["path": $0.url.path, "date": $0.date.timeIntervalSince1970, "dur": $0.duration] },
                     forKey: "recents")
    }
}

func formatTime(_ t: Double, tenths: Bool = true) -> String {
    let total = max(0, t)
    let m = Int(total) / 60
    let s = Int(total) % 60
    if tenths { return String(format: "%02d:%02d.%d", m, s, Int((total * 10).truncatingRemainder(dividingBy: 10))) }
    return String(format: "%02d:%02d", m, s)
}
