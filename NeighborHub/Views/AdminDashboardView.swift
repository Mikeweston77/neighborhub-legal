import SwiftUI
import Charts
import MapKit

struct AdminDashboardView: View {
    @State private var selectedCategory: String = "All"
    @State private var selectedDateRange: DateRange = .lastWeek
    @State private var reports: [Report] = [] // Replace with actual data source
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Trends Section
                    Text("Trends")
                        .font(.title2)
                        .bold()

                    Chart(reports) {
                        BarMark(
                            x: .value("Date", $0.date, unit: .day),
                            y: .value("Reports", $0.count)
                        )
                    }
                    .frame(height: 200)

                    // Category Breakdown
                    Text("Category Breakdown")
                        .font(.title2)
                        .bold()

                    Chart(reports) {
                        SectorMark(
                            angle: .value("Count", $0.count),
                            innerRadius: .ratio(0.5),
                            outerRadius: .ratio(1.0)
                        )
                        .foregroundStyle(by: .value("Category", $0.category))
                    }
                    .frame(height: 200)

                    // Heatmap Section
                    Text("Heatmap")
                        .font(.title2)
                        .bold()

                    Map(coordinateRegion: $mapRegion, annotationItems: reports) { report in
                        MapPin(coordinate: report.location)
                    }
                    .frame(height: 300)

                    // Response Times Section
                    Text("Response Times")
                        .font(.title2)
                        .bold()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Average Response Time: 2h 15m") // Replace with actual calculation
                        Text("Average Resolution Time: 5h 30m") // Replace with actual calculation
                    }

                    // Export & Drilldown Section
                    Button(action: exportData) {
                        Text("Export Data")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Admin Dashboard")
        }
    }

    private func exportData() {
        // Implement CSV export logic here
    }
}

struct Report: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let category: String
    let location: CLLocationCoordinate2D
}

enum DateRange: String, CaseIterable, Identifiable {
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case lastYear = "Last Year"

    var id: String { self.rawValue }
}

struct AdminDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        AdminDashboardView()
    }
}