//
//  MyCabinView.swift
//  Trucker Easy
//
//  Tab 3: Digital Document Vault
//  Features: Traffic light status, expiration tracking, photo upload
//

import SwiftUI
import PhotosUI

struct MyCabinView: View {
    @StateObject private var viewModel = CabinViewModel()
    @State private var showAddDocument = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with summary
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            StatusBadge(count: viewModel.validDocuments, color: .green, label: "Valid")
                            StatusBadge(count: viewModel.expiringDocuments, color: .orange, label: "Expiring")
                            StatusBadge(count: viewModel.expiredDocuments, color: .red, label: "Expired")
                        }
                        
                        if viewModel.expiredDocuments > 0 || viewModel.expiringDocuments > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("You have documents that need attention")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .padding(.horizontal)
                    
                    // Document types
                    VStack(spacing: 16) {
                        ForEach(DocumentType.allCases) { docType in
                            if let document = viewModel.getDocument(type: docType) {
                                DocumentCard(
                                    document: document,
                                    onUpdate: { viewModel.updateDocument(document) },
                                    onDelete: { viewModel.deleteDocument(document) }
                                )
                            } else {
                                EmptyDocumentCard(
                                    type: docType,
                                    onAdd: {
                                        viewModel.selectedDocumentType = docType
                                        showAddDocument = true
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("My Cabin")
            .sheet(isPresented: $showAddDocument) {
                if let docType = viewModel.selectedDocumentType {
                    AddDocumentSheet(documentType: docType) { document in
                        viewModel.addDocument(document)
                    }
                }
            }
        }
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let count: Int
    let color: Color
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Document Card
struct DocumentCard: View {
    let document: Document
    let onUpdate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Status indicator bar
            Rectangle()
                .fill(document.statusColor)
                .frame(height: 6)
            
            HStack(spacing: 16) {
                // Traffic light indicator
                Circle()
                    .fill(document.statusColor)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: document.statusIcon)
                            .font(.title3)
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.type.rawValue)
                        .font(.headline)
                    
                    if let expirationDate = document.expirationDate {
                        Text("Expires: \(expirationDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(document.statusMessage)
                            .font(.caption)
                            .foregroundColor(document.statusColor)
                            .fontWeight(.semibold)
                    } else {
                        Text("No expiration date set")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                // Document image thumbnail
                if let imageData = document.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                        .frame(width: 60, height: 60)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .contextMenu {
            Button {
                onUpdate()
            } label: {
                Label("Update", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Empty Document Card
struct EmptyDocumentCard: View {
    let type: DocumentType
    let onAdd: () -> Void
    
    var body: some View {
        Button {
            onAdd()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color("TruckerOrange"))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add \(type.rawValue)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Tap to upload document")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color("TruckerOrange").opacity(0.3), lineWidth: 2)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
        }
    }
}

// MARK: - Add Document Sheet
struct AddDocumentSheet: View {
    @Environment(\.dismiss) var dismiss
    let documentType: DocumentType
    var onAdd: (Document) -> Void
    
    @State private var expirationDate = Date()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showImagePicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Document Type") {
                    Text(documentType.rawValue)
                        .font(.headline)
                }
                
                Section("Expiration Date") {
                    DatePicker("Expires On", selection: $expirationDate, displayedComponents: .date)
                }
                
                Section("Document Photo") {
                    if let imageData = imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    }
                    
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        showImagePicker = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }
                
                Section {
                    Button("Save Document") {
                        let document = Document(
                            type: documentType,
                            expirationDate: expirationDate,
                            imageData: imageData
                        )
                        onAdd(document)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(imageData: $imageData)
            }
        }
    }
}

// MARK: - Image Picker (Camera)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.imageData = image.jpegData(compressionQuality: 0.8)
            }
            parent.dismiss()
        }
    }
}

#Preview {
    MyCabinView()
}
