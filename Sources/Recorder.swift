import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

enum RecorderError: LocalizedError {
    case noDisplay
    var errorDescription: String? { "Не найден дисплей для захвата" }
}

struct AppItem: Identifiable, Hashable {
    let id: String      // bundle identifier
    let name: String
}

/// Captures system (or single-app) audio via ScreenCaptureKit into a temporary float CAF file.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var file: AVAudioFile?
    private var tempURL: URL?
    private let queue = DispatchQueue(label: "marchel.records.audio", qos: .userInitiated)

    /// Peak levels per buffer (linear 0...1), called on a background queue.
    var onLevels: ((Float, Float) -> Void)?
    var onError: ((String) -> Void)?

    static func runningApps() async throws -> [AppItem] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let own = Bundle.main.bundleIdentifier ?? ""
        var seen = Set<String>()
        var items: [AppItem] = []
        for app in content.applications {
            let id = app.bundleIdentifier
            let name = app.applicationName
            if id.isEmpty || name.isEmpty || id == own || seen.contains(id) { continue }
            if id.hasPrefix("com.apple.") && !["com.apple.Safari", "com.apple.Music", "com.apple.QuickTimePlayerX",
                                                "com.apple.TV", "com.apple.podcasts", "com.apple.FaceTime",
                                                "com.apple.garageband10", "com.apple.logic10", "com.apple.FinalCut"].contains(id) {
                continue
            }
            seen.insert(id)
            items.append(AppItem(id: id, name: name))
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func start(appBundleID: String?) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let filter: SCContentFilter
        if let id = appBundleID, let app = content.applications.first(where: { $0.bundleIdentifier == id }) {
            filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }

        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48000
        cfg.channelCount = 2
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        cfg.queueDepth = 5

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("marchel-\(UUID().uuidString).caf")
        queue.sync {
            self.tempURL = url
            self.file = nil
        }

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    /// Stops capture, returns the temp file (nil if nothing was captured).
    func stop() async -> URL? {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
        var result: URL?
        queue.sync {
            let hadFile = self.file != nil
            self.file = nil            // releasing closes the file
            result = hadFile ? self.tempURL : nil
            self.tempURL = nil
        }
        return result
    }

    // MARK: SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0,
              let desc = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }
        var asbd = desc
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        guard status == noErr else { return }

        if file == nil, let url = tempURL {
            do {
                file = try AVAudioFile(forWriting: url, settings: format.settings,
                                       commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            } catch {
                onError?("Не удалось создать файл: \(error.localizedDescription)")
                return
            }
        }
        do { try file?.write(from: pcm) } catch { }

        // levels
        if let data = pcm.floatChannelData {
            let n = Int(pcm.frameLength)
            let chans = Int(format.channelCount)
            let stride = format.isInterleaved ? chans : 1
            func peak(_ ch: Int) -> Float {
                var m: Float = 0
                if format.isInterleaved {
                    let p = data[0]
                    var i = ch
                    while i < n * chans { m = max(m, abs(p[i])); i += stride }
                } else {
                    let p = data[min(ch, chans - 1)]
                    for i in 0..<n { m = max(m, abs(p[i])) }
                }
                return m
            }
            let l = peak(0)
            let r = chans > 1 ? peak(1) : l
            onLevels?(l, r)
        }
    }

    // MARK: SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?("Запись прервана: \(error.localizedDescription)")
    }
}
