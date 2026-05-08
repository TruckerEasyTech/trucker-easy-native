//
//  DashboardView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trips: [Trip]
    @Query private var expenses: [Expense]
    @Query private var fuelPurchases: [FuelPurchase]
    @Query private var documents: [TruckDocument]
    
    var activeTrip: Trip? {
        trips.first(where: { $0.isActive })
    }
    
    var thisMonthExpenses: Double {
        let calendar = Calendar.current
        let now = Date()
        return expenses.filter { expense in
            calendar.isDate(expense.date, equalTo: now, toGranularity: .month)
        }.reduce(0) { $0 + $1.amount }
    }
    
    var thisMonthMiles: Double {
        let calendar = Calendar.current
        let now = Date()
        return trips.filter { trip in
            calendar.isDate(trip.startDate, equalTo: now, toGranularity: .month)
        }.reduce(0) { $0 + $1.totalMiles }
    }
    
    var expiringDocuments: [TruckDocument] {
        documents.filter { doc in
            if let days = doc.daysUntilExpiration {
                return days <= 30 && days >= 0
            }
            return false
        }.sorted { ($0.daysUntilExpiration ?? 0) < ($1.daysUntilExpiration ?? 0) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active Trip Card
                    if let activeTrip = activeTrip {
                        ActiveTripCard(trip: activeTrip)
                    } else {
                        NewTripPromptCard()
                    }
                    
                    // Quick Stats
                    VStack(alignment: .leading, spacing: 16) {
                        Text("This Month")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            StatCard(title: "Miles", value: String(format: "%.0f", thisMonthMiles), icon: "road.lanes", color: .blue)
                            StatCard(title: "Expenses", value: String(format: "$%.2f", thisMonthExpenses), icon: "dollarsign.circle", color: .green)
                            StatCard(title: "Trips", value: "\(trips.filter { Calendar.current.isDate($0.startDate, equalTo: Date(), toGranularity: .month) }.count)", icon: "map", color: .orange)
                            StatCard(title: "Fuel Stops", value: "\(fuelPurchases.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count)", icon: "fuelpump", color: .red)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Expiring Documents Alert
                    if !expiringDocuments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Expiring Soon")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(expiringDocuments.prefix(3)) { document in
                                DocumentExpiryRow(document: document)
                            }
                        }
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Recent Expenses Chart
                    if !expenses.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Expense Breakdown")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ExpenseChartView(expenses: Array(expenses.prefix(30)))
                                .frame(height: 250)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .shadow(radius: 2)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Dashboard")
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct ActiveTripCard: View {
    let trip: Trip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.walk.departure")
                    .foregroundColor(.green)
                    .font(.title2)
                Text("Active Trip")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(trip.startLocation)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(trip.endLocation ?? "In Progress")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Miles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", trip.totalMiles))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading) {
                    Text("Fuel Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.2f", trip.totalFuelCost))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct NewTripPromptCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("No Active Trip")
                .font(.headline)
            
            Text("Start tracking your journey")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            NavigationLink(destination: AddTripView()) {
                Text("Start New Trip")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct DocumentExpiryRow: View {
    let document: TruckDocument
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading) {
                Text(document.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let days = document.daysUntilExpiration {
                    Text("Expires in \(days) days")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct ExpenseChartView: View {
    let expenses: [Expense]
    
    var categoryTotals: [CategoryTotal] {
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped.map { category, expenses in
            CategoryTotal(category: category.rawValue, total: expenses.reduce(0) { $0 + $1.amount })
        }.sorted { $0.total > $1.total }
    }
    
    var body: some View {
        Chart(categoryTotals) { item in
            BarMark(
                x: .value("Amount", item.total),
                y: .value("Category", item.category)
            )
            .foregroundStyle(by: .value("Category", item.category))
        }
    }
}

struct CategoryTotal: Identifiable {
    let id = UUID()
    let category: String
    let total: Double
}

#Preview {
    DashboardView()
        .modelContainer(for: [Trip.self, Expense.self, FuelPurchase.self, TruckDocument.self], inMemory: true)
}
