import SwiftUI

@main
struct WinUSBMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, idealWidth: 720, minHeight: 580, idealHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}
