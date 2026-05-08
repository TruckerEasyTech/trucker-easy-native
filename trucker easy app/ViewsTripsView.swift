//
//  TripsView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData

struct TripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var showingAddTrip = false
    @State private var searchText = ""
    
    var filteredTrips: [Trip] {
        if searchText.isEmpty {
            return trips
        } else {
            return trips.filter { trip in
                trip.startLocation.localizedCaseInsensitiveContains(searchText) ||
                trip.endLocation?.localizedCaseInsensitiveContains(searchText) == true ||
                trip.truckNumber.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredTrips) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        TripRow(trip: trip)
                    }
                }
                .onDelete(perform: deleteTrips)
            }
            .navigationTitle("Trips")
            .searchable(text: $searchText, prompt: "Search trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTrip = true }) {
                        Label("Add Trip", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTrip) {
                AddTripView()
            }
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips",
                        systemImage: "road.lanes",
                        description: Text("Start tracking your trips by tapping the + button")
                    )
                }
            }
        }
    }
    
    private func deleteTrips(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredTrips[index])
            }
        }
    }
}

struct TripRow: View {
    let trip: Trip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trip.startLocation)
                    .font(.headline)
                
                if trip.isActive {
                    Image(systemName: "circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Text(trip.startDate, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let endLocation = trip.endLocation {
                HStack {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(endLocation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Label(String(format: "%.1f mi", trip.totalMiles), systemImage: "road.lanes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label(String(format: "$%.2f", trip.totalFuelCost), systemImage: "fuelpump")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !trip.expenses.isEmpty {
                    Label("\(trip.expenses.count)", systemImage: "receipt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TripsView()
        .modelContainer(for: Trip.self, inMemory: true)
}
