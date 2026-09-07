import SwiftUI
import SwiftData

@main
struct MeowMoneyApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(MM.brandText)
        }
        .modelContainer(for: Expense.self)
    }
}
