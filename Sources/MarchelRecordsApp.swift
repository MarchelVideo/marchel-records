import SwiftUI
import AppKit

@main
struct MarchelRecordsApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Marchel Records", id: "main") {
            MainView()
                .environmentObject(state)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Запись") {
                Button(state.isRecording ? "Стоп" : "Запись") { state.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Открыть папку с записями") { state.openFolder() }
                    .keyboardShortcut("o")
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            Image(systemName: state.isRecording ? "record.circle.fill" : "record.circle")
        }
    }
}
