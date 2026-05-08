//import SwiftData
//  DocumentDetailView.swift
//  trucker easy app
//
//  Created by thais keller da silva  on 2/27/26.
//

import SwiftUI
import SwiftData
struct DocumentDetailView: View {
    @Bindable var document: TruckDocument
    
    var statusColor: Color {
        if document.isExpired {
            return .red
        } else if let days = document.daysUntilExpiration, days <= 30 {
            return .orange
        } else {
            return .green
        }
    }
    
    var body: some View {
        List {
            Section("Document Details") {
                LabeledContent("Name", value: document.name)
                LabeledContent("Type", value: document.documentType.rawValue)
                LabeledContent("Issue Date", value: document.issueDate, format: .dateTime.month().day().year())
                
                if let expirationDate = document.expirationDate {
                    LabeledContent("Expiration Date", value: expirationDate, format: .dateTime.month().day().year())
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                            
                            if document.isExpired {
                                Text("Expired")
                                    .foregroundColor(statusColor)
                            } else if let days = document.daysUntilExpiration {
                                if days == 0 {
                                    Text("Expires today")
                                        .foregroundColor(statusColor)
                                } else if days == 1 {
                                    Text("Expires tomorrow")
                                        .foregroundColor(statusColor)
                                } else {
                                    Text("Expires in \(days) days")
                                        .foregroundColor(statusColor)
                                }
                            } else {
                                Text("Valid")
                                    .foregroundColor(statusColor)
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                }
            }
            
            if document.reminderEnabled {
                Section("Reminder") {
                    LabeledContent("Enabled", value: "Yes")
                    LabeledContent("Remind", value: "\(document.reminderDaysBefore) days before expiration")
                }
            }
            
            if let documentData = document.documentData,
               let uiImage = UIImage(data: documentData) {
                Section("Document Scan") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                }
            }
            
            if !document.notes.isEmpty {
                Section("Notes") {
                    Text(document.notes)
                }
            }
        }
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DocumentDetailView(document: TruckDocument(
            name: "Commercial Driver's License",
            documentType: .license,
            issueDate: Date(),
            expirationDate: Calendar.current.date(byAdding: .year, value: 4, to: Date()),
            notes: "Class A CDL with hazmat endorsement"
        ))
    }
    .modelContainer(for: TruckDocument.self, inMemory: true)
}
