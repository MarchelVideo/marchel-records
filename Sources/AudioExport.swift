import Foundation
import AVFoundation

enum AudioFormat: String, CaseIterable, Identifiable {
    case wav, m4a, alac
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wav: return "WAV 24/48"
        case .m4a: return "M4A AAC 256"
        case .alac: return "ALAC без потерь"
        }
    }
    var short: String {
        switch self {
        case .wav: return "WAV 24/48"
        case .m4a: return "M4A 256"
        case .alac: return "ALAC"
        }
    }
    var ext: String { self == .wav ? "wav" : "m4a" }

    func settings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        switch self {
        case .wav:
            return [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false]
        case .m4a:
            return [AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: 256_000]
        case .alac:
            return [AVFormatIDKey: kAudioFormatAppleLossless,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitDepthHintKey: 24]
        }
    }
}

enum AudioExport {
    /// Converts the temp capture to the chosen format, optionally trimming leading/trailing silence.
    /// Returns duration in seconds, or nil if the recording was entirely silent.
    static func export(from src: URL, to dst: URL, format: AudioFormat, trim: Bool) throws -> Double? {
        let input = try AVAudioFile(forReading: src)
        let pf = input.processingFormat
        let total = input.length
        guard total > 0 else { return nil }
        let chunk: AVAudioFrameCount = 8192
        guard let buf = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: chunk) else { return nil }

        var start: AVAudioFramePosition = 0
        var end: AVAudioFramePosition = total

        if trim {
            let threshold: Float = 0.001     // −60 dBFS
            var first: AVAudioFramePosition = -1
            var last: AVAudioFramePosition = -1
            input.framePosition = 0
            var pos: AVAudioFramePosition = 0
            while pos < total {
                try input.read(into: buf, frameCount: chunk)
                let n = Int(buf.frameLength)
                if n == 0 { break }
                if let d = buf.floatChannelData {
                    for i in 0..<n {
                        var loud = false
                        for c in 0..<Int(pf.channelCount) where abs(d[c][i]) > threshold { loud = true; break }
                        if loud {
                            if first < 0 { first = pos + AVAudioFramePosition(i) }
                            last = pos + AVAudioFramePosition(i)
                        }
                    }
                }
                pos += AVAudioFramePosition(n)
            }
            if first < 0 { return nil }
            let pad = AVAudioFramePosition(pf.sampleRate * 0.05)   // keep 50 ms of air
            start = max(0, first - pad)
            end = min(total, last + pad)
        }

        let out = try AVAudioFile(forWriting: dst,
                                  settings: format.settings(sampleRate: pf.sampleRate, channels: pf.channelCount),
                                  commonFormat: .pcmFormatFloat32,
                                  interleaved: false)
        input.framePosition = start
        var remaining = end - start
        while remaining > 0 {
            let want = AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining))
            try input.read(into: buf, frameCount: want)
            if buf.frameLength == 0 { break }
            try out.write(from: buf)
            remaining -= AVAudioFramePosition(buf.frameLength)
        }
        return Double(end - start) / pf.sampleRate
    }
}
