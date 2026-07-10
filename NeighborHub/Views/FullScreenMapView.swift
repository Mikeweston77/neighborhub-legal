import MapKit
import SwiftUI

struct FullScreenMapView: View {
    @Binding var mapRegion: MKCoordinateRegion
    let pins: [MapPin]
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(coordinateRegion: $mapRegion, annotationItems: pins) { pin in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)) {
                        VStack {
                            if pin.isCurrentUser {
                                Image(systemName: "location.north.fill")
                                    .font(.title)
                                    .foregroundColor(pin.freshnessColor ?? .blue)
                            } else {
                                Circle()
                                    .fill(pin.freshnessColor ?? .gray)
                                    .frame(width: 36, height: 36)
                                    .overlay(Text(pin.initials).foregroundColor(.white).font(.caption2))
                            }
                        }
                    }
                }
                .ignoresSafeArea()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .padding(12)
                        .background(.thinMaterial)
                        .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    struct MapPin: Identifiable {
        let id: String
        let latitude: Double
        let longitude: Double
        let initials: String
        let isCurrentUser: Bool
        let freshnessColor: Color?
    }
}
