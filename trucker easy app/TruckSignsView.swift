import SwiftUI

// TruckSign and TruckSignsView intentionally keep sign titles/descriptions in English
// because these are official road sign names used in the USA. Navigation title and
// UI chrome are localized via RegionalSettingsManager.
struct TruckSign: Identifiable, Hashable {
    let id = UUID()
    let icon: String       // SF Symbol fallback
    let title: String
    let description: String
    let category: Category

    enum Category: String, CaseIterable, Hashable {
        case restrictions = "Restrictions"
        case weighStations = "Weigh Stations"
        case hazards = "Hazards"
        case parking = "Parking"
        case lanes = "Lanes & Turns"
        case speed = "Speed & Limits"
    }
}

struct TruckSignsView: View {
    @Environment(RegionalSettingsManager.self) private var regionalSettings
    @State private var query: String = ""
    @State private var selectedCategory: TruckSign.Category? = nil

    var lang: AppLanguage { regionalSettings.currentLanguage }

    private var allSigns: [TruckSign] = [
        TruckSign(icon: "scalemass.fill", title: "Weigh Station", description: "Upcoming weigh station. Trucks must follow posted instructions. Some stations require all trucks to enter when open.", category: .weighStations),
        TruckSign(icon: "scalemass", title: "Weigh Station Closed", description: "Weigh station is closed. Proceed without entering unless instructed otherwise.", category: .weighStations),
        TruckSign(icon: "car.side.2", title: "Truck Route", description: "Designated truck route. Prefer these roads to avoid restrictions and low-clearance obstacles.", category: .lanes),
        TruckSign(icon: "road.lanes", title: "No Trucks", description: "Road is closed to trucks. Find alternate route immediately.", category: .restrictions),
        TruckSign(icon: "arrow.down.to.line", title: "Low Bridge", description: "Low clearance ahead. Verify your vehicle height and compare with posted clearance.", category: .hazards),
        TruckSign(icon: "arrow.up.and.down", title: "Height Limit", description: "Maximum vehicle height allowed. Ensure your total height (tractor + trailer) is within the limit.", category: .restrictions),
        TruckSign(icon: "scalemass.fill", title: "Weight Limit", description: "Maximum gross weight allowed on this road/bridge. Check your current load and axle weights.", category: .restrictions),
        TruckSign(icon: "biohazard", title: "HAZMAT Restricted", description: "Hazardous materials restricted or prohibited. Follow designated HAZMAT routes.", category: .restrictions),
        TruckSign(icon: "p.circle.fill", title: "Truck Parking", description: "Designated truck parking area. Follow posted time limits and reservations if applicable.", category: .parking), 
        TruckSign(icon: "signpost.right.fill", title: "Lane Restriction", description: "Trucks restricted to specific lanes. Keep right unless passing where allowed.", category: .lanes),
        TruckSign(icon: "gauge.with.dots.needle.67percent", title: "Speed Limit (Trucks)", description: "Posted speed limit specific to trucks. Obey lower limits where posted.", category: .speed)
    ]

    private var filteredSigns: [TruckSign] {
        let base = selectedCategory == nil ? allSigns : allSigns.filter { $0.category == selectedCategory }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return base }
        let q = query.lowercased()
        return base.filter { $0.title.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(lang.searchSignsLabel, text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 12)

                // Category chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(action: { selectedCategory = nil }) {
                            chip(label: lang.allCategoryLabel, isSelected: selectedCategory == nil)
                        }
                        ForEach(TruckSign.Category.allCases, id: \.self) { cat in
                            Button(action: { selectedCategory = cat }) {
                                chip(label: cat.rawValue, isSelected: selectedCategory == cat)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // List of signs
                List(filteredSigns) { sign in
                    NavigationLink(value: sign) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.blue.opacity(0.15)).frame(width: 40, height: 40)
                                Image(systemName: sign.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sign.title).font(.system(size: 15, weight: .semibold))
                                Text(sign.description).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
            .navigationDestination(for: TruckSign.self) { sign in
                TruckSignDetailView(sign: sign)
            }
            .navigationTitle(lang.truckSignsTitle)
        }
    }

    private func chip(label: String, isSelected: Bool) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isSelected ? .white : .blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.blue.opacity(0.12))
            .cornerRadius(20)
    }
}

struct TruckSignDetailView: View {
    let sign: TruckSign

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.15)).frame(width: 56, height: 56)
                        Image(systemName: sign.icon)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    Text(sign.title)
                        .font(.system(size: 22, weight: .bold))
                }

                Text(sign.description)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)

                Divider()

                // Practical tips for drivers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Driver Tips")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                    Group {
                        if sign.title.contains("Weigh Station") {
                            Text("• Prepare to stop when open. Follow posted speed and lane instructions.")
                            Text("• Keep documents ready (registration, permits).")
                        } else if sign.title.contains("HAZMAT") {
                            Text("• Verify your cargo class. Use designated HAZMAT routes only.")
                            Text("• Check tunnels/bridges with HAZMAT restrictions.")
                        } else if sign.title.contains("Weight") {
                            Text("• Confirm axle and gross weights. Consider alternate routes if overweight.")
                        } else if sign.title.contains("Low Bridge") || sign.title.contains("Height") {
                            Text("• Compare posted clearance with your rig height. Do not attempt if uncertain.")
                        } else if sign.title.contains("No Trucks") {
                            Text("• Plan alternate route. Use truck-designated roads to avoid fines.")
                        } else if sign.title.contains("Speed") {
                            Text("• Obey truck-specific speed limits. They may be lower than general traffic.")
                        } else if sign.title.contains("Parking") {
                            Text("• Park only in designated truck areas. Respect time limits and reservations.")
                        } else {
                            Text("• Follow posted instructions and plan ahead.")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle(sign.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    TruckSignsView()
        .environment(RegionalSettingsManager())
}
