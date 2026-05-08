//
//  MyCabinViewFixed.swift
//  Trucker Easy
//
//  COFRE DE DOCUMENTOS FUNCIONANDO - 100% NATIVO
//

import SwiftUI
import PhotosUI

struct MyCabinViewFixed: View {
    @StateObject private var viewModel = CabinViewModelWorking()
    @State private var showAddDocument = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // RESUMO COM SEMÁFORO
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            StatusBadgeWorking(count: viewModel.validDocuments, color: .green, label: "Valid")
                            StatusBadgeWorking(count: viewModel.expiringDocuments, color: .orange, label: "Expiring")
                            StatusBadgeWorking(count: viewModel.expiredDocuments, color: .red, label: "Expired")
                        }
                        
                        if viewModel.expiredDocuments > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("You have expired documents!")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        } else if viewModel.expiringDocuments > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(viewModel.expiringDocuments) document(s) expiring soon")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
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
                    .shadow(color: .black.opacity(0.05), radius: 8)
                    .padding(.horizontal)
                    
                    // LISTA DE DOCUMENTOS
                    VStack(spacing: 16) {
                        ForEach(DocumentType.allCases) { docType in
                            if let document = viewModel.getDocument(type: docType) {
                                DocumentCardWorking(
                                    document: document,
                                    onUpdate: {
                                        viewModel.selectedDocumentType = docType
                                        showAddDocument = true
                                    },
                                    onDelete: {
                                        viewModel.deleteDocument(document)
                                    }
                                )
                            } else {
                                EmptyDocumentCardWorking(
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
                    AddDocumentSheetWorking(documentType: docType) { document in
                        viewModel.addDocument(document)
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadMockDocuments()
        }
    }
}

// Badge de status
struct StatusBadgeWorking: View {
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

// Card de documento FUNCIONANDO
struct DocumentCardWorking: View {
    let document: Document
    let onUpdate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Barra de status colorida no topo
            Rectangle()
                .fill(document.statusColor)
                .frame(height: 6)
            
            HStack(spacing: 16) {
                // Círculo de status (semáforo)
                ZStack {
                    Circle()
                        .fill(document.statusColor)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: document.statusIcon)
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
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
                
                // Thumbnail da imagem
                if let imageData = document.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .clipped()
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
        .shadow(color: .black.opacity(0.05), radius: 8)
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

// Card vazio para adicionar documento
struct EmptyDocumentCardWorking: View {
    let type: DocumentType
    let onAdd: () -> Void
    
    var body: some View {
        Button {
            onAdd()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
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
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(.orange.opacity(0.3))
            )
        }
    }
}

// Sheet para adicionar/editar documento
struct AddDocumentSheetWorking: View {
    @Environment(\.dismiss) var dismiss
    let documentType: DocumentType
    var onAdd: (Document) -> Void
    
    @State private var expirationDate = Date().addingTimeInterval(365 * 24 * 60 * 60) // 1 ano
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showCamera = false
    
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
                        
                        Button("Change Photo") {
                            self.imageData = nil
                        }
                        .foregroundColor(.orange)
                    } else {
                        VStack(spacing: 16) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Choose from Photos", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            
                            Button {
                                showCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                
                Section {
                    Button {
                        let document = Document(
                            type: documentType,
                            expirationDate: expirationDate,
                            imageData: imageData
                        )
                        onAdd(document)
                        
                        // Haptic
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save Document")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(imageData == nil)
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
            .sheet(isPresented: $showCamera) {
                ImagePickerWorking(imageData: $imageData)
            }
        }
    }
}

// Camera picker FUNCIONANDO
struct ImagePickerWorking: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraDevice = .rear
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerWorking
        
        init(_ parent: ImagePickerWorking) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.imageData = image.jpegData(compressionQuality: 0.8)
                print("✅ Foto capturada!")
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// ViewModel FUNCIONANDO
@MainActor
class CabinViewModelWorking: ObservableObject {
    @Published var documents: [Document] = []
    @Published var selectedDocumentType: DocumentType?
    
    var validDocuments: Int {
        documents.filter { $0.statusColor == .green }.count
    }
    
    var expiringDocuments: Int {
        documents.filter { $0.statusColor == .orange }.count
    }
    
    var expiredDocuments: Int {
        documents.filter { $0.statusColor == .red }.count
    }
    
    func loadMockDocuments() {
        print("📄 Carregando documentos mock...")
        
        // Criar documentos de exemplo
        documents = [
            Document(
                type: .cdl,
                expirationDate: Date().addingTimeInterval(180 * 24 * 60 * 60), // 180 dias (verde)
                imageData: nil
            ),
            Document(
                type: .medicalCard,
                expirationDate: Date().addingTimeInterval(20 * 24 * 60 * 60), // 20 dias (amarelo)
                imageData: nil
            )
        ]
        
        print("✅ \(documents.count) documentos carregados")
    }
    
    func getDocument(type: DocumentType) -> Document? {
        documents.first { $0.type == type }
    }
    
    func addDocument(_ document: Document) {
        print("➕ Adicionando documento: \(document.type.rawValue)")
        
        // Remover documento antigo do mesmo tipo
        documents.removeAll { $0.type == document.type }
        
        // Adicionar novo
        documents.append(document)
        
        // TODO: Salvar no Supabase
    }
    
    func deleteDocument(_ document: Document) {
        print("🗑️ Deletando documento: \(document.type.rawValue)")
        documents.removeAll { $0.id == document.id }
        
        // TODO: Deletar do Supabase
    }
}

#Preview {
    MyCabinViewFixed()
}
