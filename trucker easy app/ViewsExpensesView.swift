//
//  ExpensesView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData
import Charts

struct ExpensesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showingAddExpense = false
    @State private var selectedCategory: ExpenseCategory?
    @State private var searchText = ""
    
    var filteredExpenses: [Expense] {
        var result = expenses
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            result = result.filter { expense in
                expense.vendorName.localizedCaseInsensitiveContains(searchText) ||
                expense.notes.localizedCaseInsensitiveContains(searchText) ||
                expense.location.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    var categoryTotals: [CategoryTotal] {
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped.map { category, expenses in
            CategoryTotal(category: category.rawValue, total: expenses.reduce(0) { $0 + $1.amount })
        }.sorted { $0.total > $1.total }
    }
    
    var totalExpenses: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary Card
                VStack(spacing: 12) {
                    Text(String(format: "$%.2f", totalExpenses))
                        .font(.system(size: 36, weight: .bold))
                    
                    Text("Total Expenses")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !categoryTotals.isEmpty {
                        Chart(categoryTotals) { item in
                            SectorMark(
                                angle: .value("Amount", item.total),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("Category", item.category))
                        }
                        .frame(height: 200)
                        .padding()
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(
                            title: "All",
                            isSelected: selectedCategory == nil,
                            action: { selectedCategory = nil }
                        )
                        
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            FilterChip(
                                title: category.rawValue,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                
                // Expenses List
                List {
                    ForEach(filteredExpenses) { expense in
                        NavigationLink(destination: ExpenseDetailView(expense: expense)) {
                            ExpenseRow(expense: expense)
                        }
                    }
                    .onDelete(perform: deleteExpenses)
                }
            }
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Search expenses")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddExpense = true }) {
                        Label("Add Expense", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseView()
            }
            .overlay {
                if expenses.isEmpty {
                    ContentUnavailableView(
                        "No Expenses",
                        systemImage: "dollarsign.circle",
                        description: Text("Track your expenses by tapping the + button")
                    )
                }
            }
        }
    }
    
    private func deleteExpenses(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredExpenses[index])
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

#Preview {
    ExpensesView()
        .modelContainer(for: Expense.self, inMemory: true)
}
