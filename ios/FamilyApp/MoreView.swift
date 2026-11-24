import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("More", selection: $app.moreSection) {
                Text("Marriage").tag(AppTab.marriage)
                Text("Food").tag(AppTab.food)
                Text("Vacations").tag(AppTab.vacations)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                switch app.moreSection {
                case .food:
                    FoodTabView()
                case .vacations:
                    VacationsView()
                default:
                    MarriageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
    }
}
