import ComposerUI
import SwiftUI

@main
struct ComposerUIApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(model)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project…") { model.openProjectFromPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Console") { model.console.isExpanded.toggle() }
                    .keyboardShortcut("`", modifiers: .command)
            }
        }
    }
}
