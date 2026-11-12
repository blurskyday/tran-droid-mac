import SwiftUI
import AppKit

@main
struct tranandroiApp: App {
    @StateObject private var vm = AppViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("tranandroi") {
            ContentView(vm: vm)
                .frame(minWidth: 920, minHeight: 580)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Folder") {
                    vm.newFolderName = "untitled folder"
                    vm.showNewFolderSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Upload from Mac to Android...") {
                    vm.uploadFromMacPrompt()
                }
                .keyboardShortcut("u", modifiers: [.command])

                Button("Download Selected to Mac...") {
                    vm.downloadSelectedAndroidItemsToMacPrompt()
                }
                .keyboardShortcut("d", modifiers: [.command])
            }

            CommandMenu("View") {
                Button("as Icons") {
                    vm.viewMode = .icons
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("as List") {
                    vm.viewMode = .list
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("as Columns") {
                    vm.viewMode = .columns
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("as Gallery") {
                    vm.viewMode = .gallery
                }
                .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Toggle("Dual-Pane Mac ↔ Android Split", isOn: $vm.showDualPaneMacSplit)
                    .keyboardShortcut("s", modifiers: [.command, .option])

                Toggle("Show Path Bar", isOn: $vm.showPathBar)
                    .keyboardShortcut("p", modifiers: [.command, .option])

                Toggle("Show Status Bar", isOn: $vm.showStatusBar)
                    .keyboardShortcut("/", modifiers: [.command])

                Toggle("Show Preview / Inspector", isOn: $vm.showInspectorPane)
                    .keyboardShortcut("i", modifiers: [.command, .option])

                Divider()

                Button("Refresh / Reconnect USB") {
                    Task {
                        if vm.connectedDevice == nil {
                            await vm.connectAndroidDevice()
                        } else {
                            await vm.reloadCurrentDirectory()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Go") {
                Button("Back") {
                    vm.goBack()
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!vm.canGoBack)

                Button("Forward") {
                    vm.goForward()
                }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(!vm.canGoForward)

                Divider()

                ForEach(vm.androidQuickFolders, id: \.name) { fav in
                    Button("Android: \(fav.name)") {
                        Task {
                            await vm.openAndroidQuickFolder(name: fav.name, pathComponents: fav.path)
                        }
                    }
                }
            }
        }
    }
}
