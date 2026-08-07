import SwiftUI
import SwiftData

@main
struct MeowMoneyApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(Cute.peach)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: Expense.self)
    }
}
