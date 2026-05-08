//
//  DocumentsView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData

struct DocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TruckDocument.expirationDate) private var documents: [TruckDocument]
    @State private var showingAddDocument = false
    @State private var selectedFilter: DocumentFilter = .all
    
    enum DocumentFilter {
        case all, expiring, expired
    }
    
    var filteredDocuments: [TruckDocument] {
        switch selectedFilter {
        case .all:
            return documents
        case .expiring:
            return documents.filter { doc in
                if let days = doc.daysUntilExpiration {
                    return days <= 30 && days >= 0
                }
                return false
            }
        case .expired:
            return documents.filter { $0.isExpired }
        }
    }
    
    var expiringCount: Int {
        documents.filter { doc in
            if let days = doc.daysUntilExpiration {
                return days <= 30 && days >= 0
            }
            return false
        }.count
    }
    
    var expiredCount: Int {
        documents.filter { $0.isExpired }.count
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Buttons
                if !documents.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            FilterButton(
                                title: "All",
                                count: documents.count,
                                isSelected: selectedFilter == .all,
                                action: { selectedFilter = .all }
                            )
                            
                            FilterButton(
                                title: "Expiring Soon",
                                count: expiringCount,
                                isSelected: selectedFilter == .expiring,
                                color: .orange,
                                action: { selectedFilter = .expiring }
                            )
                            
                            FilterButton(
                                title: "Expired",
                                count: expiredCount,
                                isSelected: selectedFilter == .expired,
                                color: .red,
                                action: { selectedFilter = .expired }
                            )
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
                
                // Documents List
                List {
                    ForEach(filteredDocuments) { document in
                        NavigationLink(destination: DocumentDetailView(document: document)) {
                            DocumentRow(document: document)
                        }
                    }
                    .onDelete(perform: deleteDocuments)
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddDocument = true }) {
                        Label("Add Document", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDocument) {
                AddDocumentView()
            }
            .overlay {
                if documents.isEmpty {
                    ContentUnavailableView(
                        "No Documents",
                        systemImage: "folder",
                        description: Text("Store your important trucking documents here")
                    )
                }
            }
        }
    }
    
    private func deleteDocuments(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredDocuments[index])
            }
        }
    }
}

struct FilterButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : color.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

struct DocumentRow: View {
    let document: TruckDocument
    
    var statusColor: Color {
        if document.isExpired {
            return .red
        } else if let days = document.daysUntilExpiration, days <= 30 {
            return .orange
        } else {
            return .green
        }
    }
    
    var statusText: String {
        if document.isExpired {
            return "Expired"
        } else if let days = document.daysUntilExpiration {
            if days == 0 {
                return "Expires today"
            } else if days == 1 {
                return "Expires tomorrow"
            } else if days <= 30 {
                return "Expires in \(days) days"
            } else {
                return "Valid"
            }
        } else {
            return "No expiration"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.name)
                        .font(.headline)
                    
                    Text(document.documentType.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let expirationDate = document.expirationDate {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(statusColor)
                        }
                        
                        Text(expirationDate, format: .dateTime.month().day().year())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DocumentsView()
        .modelContainer(for: TruckDocument.self, inMemory: true)
}
