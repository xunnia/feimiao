import SwiftUI
import SwiftData

@main
struct QingJiApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    DataSeeder.seedIfNeeded(context: AppModelContainer.shared.mainContext)
                }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
