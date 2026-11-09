import SwiftUI
import AppKit

enum Theme {
    static let cream = Color(hex: 0xEDE6DA)
    static let paper = Color(hex: 0xF7F2E9)
    static let ink = Color(hex: 0x2B2420)
    static let muted = Color(hex: 0x6B5E50)
    static let line = Color(hex: 0xCFC5B5)
    static let dashed = Color(hex: 0xBFB3A2)
    static let accent = Color(hex: 0xD9480F)
    static let accentShadow = Color(hex: 0x8A3407)
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Main window
struct MainView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    VUMeter(level: state.levelL, caption: "LEFT", db: state.dbL, active: state.isRecording)
                    VUMeter(level: state.levelR, caption: "RIGHT", db: state.dbR, active: state.isRecording)
                }
                CounterDisplay()
                Controls()
                SettingsRows()
                TapeLog()
                if !state.status.isEmpty {
                    Text(state.status)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            Spacer(minLength: 0)
        }
        .frame(width: 440)
        .frame(minHeight: 700)
        .background(Theme.cream)
        .foregroundColor(Theme.ink)
        .ignoresSafeArea()
        .task { await state.refreshApps() }
    }
}

struct TitleBar: View {
    var body: some View {
        ZStack {
            Theme.ink
            Text("MARCHEL RECORDS")
                .font(Theme.mono(13, .semibold))
                .tracking(2.4)
                .foregroundColor(Theme.cream)
        }
        .frame(height: 44)
    }
}

// MARK: - VU meter
struct VUMeter: View {
    var level: Double
    var caption: String
    var db: Double
    var active: Bool

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height - 6)
                let radius = min(size.width / 2 - 14, size.height - 16)
                let a0 = 215.0, a1 = 325.0
                func pt(_ deg: Double, _ r: CGFloat) -> CGPoint {
                    let rad = deg * .pi / 180
                    return CGPoint(x: center.x + r * CGFloat(cos(rad)), y: center.y + r * CGFloat(sin(rad)))
                }
                func arc(_ from: Double, _ to: Double, _ r: CGFloat) -> Path {
                    var p = Path()
                    let steps = 40
                    for i in 0...steps {
                        let d = from + (to - from) * Double(i) / Double(steps)
                        if i == 0 { p.move(to: pt(d, r)) } else { p.addLine(to: pt(d, r)) }
                    }
                    return p
                }
                // scale
                ctx.stroke(arc(a0, a1, radius), with: .color(Theme.line), lineWidth: 2)
                let zeroDeg = a0 + (a1 - a0) * (20.0 / 23.0)
                ctx.stroke(arc(zeroDeg, a1, radius), with: .color(Theme.accent), lineWidth: 4)
                // ticks at −20 −10 −7 −5 −3 0 +3
                for d in [-20.0, -10, -7, -5, -3, 0, 3] {
                    let deg = a0 + (a1 - a0) * ((d + 20) / 23)
                    var t = Path()
                    t.move(to: pt(deg, radius - 4))
                    t.addLine(to: pt(deg, radius - 11))
                    ctx.stroke(t, with: .color(d >= 0 ? Theme.accent : Theme.muted), lineWidth: 1.5)
                }
                ctx.draw(Text("VU").font(Theme.mono(9, .semibold)).foregroundColor(Theme.muted),
                         at: CGPoint(x: center.x, y: center.y - radius * 0.45))
                // needle
                let nd = a0 + (a1 - a0) * level
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: pt(nd, radius + 2))
                ctx.stroke(needle, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                         with: .color(Theme.ink))
            }
            .frame(height: 80)
            Text(active ? "\(caption) · \(String(format: "%.0f", max(db, -60))) dB" : "\(caption) · —")
                .font(Theme.mono(11))
                .foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Counter
struct CounterDisplay: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isRecording ? "REC · \(state.sourceName.uppercased())" : "ГОТОВ · \(state.sourceName.uppercased())")
                    .font(Theme.mono(11))
                    .tracking(1.3)
                    .foregroundColor(Theme.dashed)
                    .lineLimit(1)
                Text(formatTime(state.elapsed))
                    .font(Theme.mono(38))
                    .monospacedDigit()
                    .foregroundColor(Theme.paper)
            }
            Spacer()
            Circle()
                .fill(state.isRecording ? Theme.accent : Theme.muted)
                .frame(width: 12, height: 12)
                .opacity(state.isRecording && Int(state.elapsed * 2) % 2 == 1 ? 0.25 : 1)
                .animation(.easeInOut(duration: 0.25), value: Int(state.elapsed * 2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Controls
struct Controls: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                Button("Вся система") { state.selectSource(nil) }
                Divider()
                if state.apps.isEmpty {
                    Text("Нет приложений со звуком")
                } else {
                    ForEach(state.apps) { app in
                        Button(app.name) { state.selectSource(app) }
                    }
                }
                Divider()
                Button("Обновить список") { Task { await state.refreshApps() } }
            } label: {
                PillLabel(text: "ИСТОЧНИК ▾")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(state.isRecording)

            RecordButton()

            Menu {
                ForEach(AudioFormat.allCases) { f in
                    Button(f.label) { state.format = f }
                }
            } label: {
                PillLabel(text: state.format.short)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(state.isRecording)
        }
    }
}

struct PillLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Theme.mono(12, .semibold))
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.paper)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct RecordButton: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button(action: { state.toggle() }) {
            ZStack {
                if state.isRecording {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.paper).frame(width: 24, height: 24)
                } else {
                    Circle().fill(Theme.paper).frame(width: 26, height: 26)
                }
            }
            .frame(width: 76, height: 76)
        }
        .buttonStyle(TapeKeyStyle())
        .disabled(state.busy)
        .help(state.isRecording ? "Стоп (⌥⌘R)" : "Запись (⌥⌘R)")
        .accessibilityLabel(state.isRecording ? "Остановить запись" : "Начать запись")
    }
}

struct TapeKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Theme.accent))
            .background(Circle().fill(Theme.accentShadow).offset(y: configuration.isPressed ? 1 : 4))
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Settings rows
struct SettingsRows: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Обрезать тишину")
                Spacer()
                Toggle("", isOn: $state.trimSilence)
                    .toggleStyle(.switch)
                    .tint(Theme.ink)
                    .labelsHidden()
                    .controlSize(.small)
            }
            HStack {
                Text("Горячая клавиша")
                Spacer()
                Text("⌥ ⌘ R").font(Theme.mono(13)).foregroundColor(Theme.muted)
            }
            HStack {
                Text("Папка")
                Spacer()
                Button(action: { state.chooseFolder() }) {
                    Text(state.folder.lastPathComponent)
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(state.folder.path)
                Button(action: { state.openFolder() }) {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Открыть папку")
                .accessibilityLabel("Открыть папку")
            }
        }
        .font(.system(size: 13))
    }
}

// MARK: - Tape log
struct TapeLog: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DashedLine().stroke(Theme.dashed, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            Text("TAPE LOG").font(Theme.mono(11)).tracking(1.3).foregroundColor(Theme.muted).padding(.top, 4)
            if state.recents.isEmpty {
                Text("Записей пока нет").font(Theme.mono(12)).foregroundColor(Theme.muted).frame(height: 28)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(state.recents.enumerated()), id: \.element.id) { i, r in
                            LogRow(index: i + 1, rec: r)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }
}

struct LogRow: View {
    @EnvironmentObject var state: AppState
    var index: Int
    var rec: Recording

    private static let df: DateFormatter = {
        let d = DateFormatter(); d.dateFormat = "dd.MM HH:mm"; return d
    }()

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d · %@", index, LogRow.df.string(from: rec.date)))
            Spacer()
            Text(formatTime(rec.duration, tenths: false)).foregroundColor(Theme.muted)
            Button(action: { state.togglePlay(rec) }) {
                Image(systemName: state.playingURL == rec.url ? "stop.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.playingURL == rec.url ? "Стоп" : "Воспроизвести")
            Button(action: { state.reveal(rec) }) {
                Image(systemName: "folder").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Показать в Finder")
        }
        .font(Theme.mono(12))
        .frame(height: 28)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: rec.url) ?? NSItemProvider() }
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

// MARK: - Menu bar
struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(state.isRecording ? "■ Стоп — \(formatTime(state.elapsed, tenths: false))" : "● Запись") { state.toggle() }
            .keyboardShortcut("r", modifiers: [.command, .option])
        Text("Источник: \(state.sourceName)")
        Divider()
        Button("Открыть Marchel Records") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Открыть папку с записями") { state.openFolder() }
        Divider()
        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
