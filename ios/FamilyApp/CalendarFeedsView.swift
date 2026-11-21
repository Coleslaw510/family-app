import SwiftUI

struct CalendarFeedsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var feeds: [CalendarFeed] = []
    @State private var name = ""
    @State private var url = ""
    @State private var color = "#7c3aed"
    @State private var error: String?
    private let colors = ["#4285F4", "#E67C73", "#33B679", "#7C3AED", "#EA580C"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Family-wide, read-only. The server checks each feed about every 15 minutes. The full address is stored on the server and is not shown again.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    ForEach(feeds) { feed in
                        Card {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle().fill(Color(hexString: feed.color)).frame(width: 10, height: 10)
                                    Text(feed.name).font(.system(size: 15, weight: .bold))
                                    Spacer()
                                    Button("Remove") { Task { await remove(feed) } }
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Theme.bad)
                                }
                                Text(feed.urlMasked).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                                Text("\(feed.eventCount) events")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.soft)
                                if let problem = feed.lastError {
                                    Text(problem).font(.system(size: 12)).foregroundStyle(Theme.warn)
                                }
                            }
                        }
                    }
                    LabeledInput(title: "Name", text: $name, autocap: .words)
                    LabeledInput(title: "Secret iCal URL", text: $url, keyboard: .URL, autocap: .never)
                    HStack {
                        ForEach(colors, id: \.self) { item in
                            Button { color = item } label: {
                                Circle().fill(Color(hexString: item)).frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.white, lineWidth: color == item ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    PrimaryButton(title: "Add feed") { Task { await add() } }
                    if let error {
                        Text(error).foregroundStyle(Theme.bad)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Calendar feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await reload() }
        }
    }

    private func reload() async {
        if let list: FeedList = try? await app.api.get("/v1/calendar-feeds") {
            feeds = list.feeds
        }
    }

    private func add() async {
        do {
            let _: CalendarFeed = try await app.api.post("/v1/calendar-feeds", body: FeedBody(name: name, color: color, url: url))
            name = ""
            url = ""
            error = nil
            await reload()
            await app.refreshAll(silent: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ feed: CalendarFeed) async {
        do {
            let _: JSONAck = try await app.api.delete("/v1/calendar-feeds/\(feed.id)")
            await reload()
            await app.refreshAll(silent: true)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
