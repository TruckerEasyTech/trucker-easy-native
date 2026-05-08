import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

// MARK: - Document Camera Scanner (VisionKit wrapper)

struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: (UIImage) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Take the first scanned page and compress it
            let image = scan.imageOfPage(at: 0)
            controller.dismiss(animated: true) { [weak self] in
                self?.onScan(image)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) { [weak self] in
                self?.onCancel()
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true) { [weak self] in
                self?.onCancel()
            }
        }
    }
}

// MARK: - Add Document View (camera-first, truck driver friendly)

struct AddDocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Pre-filled when launched from a Quick Scan button (e.g. "CDL License")
    var presetName: String = ""
    var presetType: DocumentType = .other

    @State private var name: String = ""
    @State private var documentType: DocumentType = .other
    @State private var issueDate = Date()
    @State private var hasExpiration = true
    @State private var expirationDate = Date().addingTimeInterval(365 * 24 * 60 * 60)
    @State private var notes = ""
    @State private var reminderEnabled = true
    @State private var reminderDaysBefore = 30
    @State private var documentImage: UIImage? = nil
    @State private var documentData: Data? = nil

    // Sheet controls
    @State private var showingScanner = false
    @State private var showingPhotosPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingImageSourcePicker = false
    @State private var showingDetails = false  // expands the details form

    var canSave: Bool { !name.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── Scan area ────────────────────────────────────────
                        scanArea
                            .padding(.top, 16)
                            .padding(.horizontal, 20)

                        // ── Document name (auto-filled from preset) ──────────
                        nameField
                            .padding(.top, 20)
                            .padding(.horizontal, 20)

                        // ── Quick type selector ──────────────────────────────
                        typeSelector
                            .padding(.top, 16)
                            .padding(.horizontal, 20)

                        // ── Expiry date — most important for compliance ───────
                        expirySection
                            .padding(.top, 16)
                            .padding(.horizontal, 20)

                        // ── Reminder toggle ───────────────────────────────────
                        reminderRow
                            .padding(.top, 12)
                            .padding(.horizontal, 20)

                        // ── Notes (optional, collapsed) ───────────────────────
                        if showingDetails {
                            notesField
                                .padding(.top, 12)
                                .padding(.horizontal, 20)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // ── Show / hide extra details ─────────────────────────
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) { showingDetails.toggle() }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12))
                                Text(showingDetails ? "Less" : "Add Notes")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .padding(.top, 10)
                        }

                        // ── Save button ────────────────────────────────────────
                        saveButton
                            .padding(.top, 24)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            // VisionKit document scanner
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScanner(
                    onScan: { image in
                        documentImage = image
                        documentData = image.jpegData(compressionQuality: 0.85)
                        showingScanner = false
                    },
                    onCancel: { showingScanner = false }
                )
                .ignoresSafeArea()
            }
            // Photo library fallback
            .photosPicker(
                isPresented: $showingPhotosPicker,
                selection: $selectedPhoto,
                matching: .images
            )
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        documentData = data
                        documentImage = UIImage(data: data)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                // Pre-fill from preset if provided
                if !presetName.isEmpty {
                    name = presetName
                    documentType = presetType
                }
            }
        }
    }

    // MARK: - Scan Area

    private var scanArea: some View {
        VStack(spacing: 0) {
            if let image = documentImage {
                // Scanned preview
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AppTheme.Colors.accent.opacity(0.5), lineWidth: 1.5)
                        )
                    // Re-scan button
                    Button(action: { showingImageSourcePicker = true }) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding(10)
                }
            } else {
                // Camera / library CTA — large and tap-friendly
                Button(action: {
                    if VNDocumentCameraViewController.isSupported {
                        showingScanner = true
                    } else {
                        showingPhotosPicker = true
                    }
                }) {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.accent.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Image(systemName: "doc.viewfinder.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundColor(AppTheme.Colors.accent)
                        }
                        Text("Tap to Scan Document")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Text("Camera opens automatically — no typing needed")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(AppTheme.Colors.backgroundCard)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1.5)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )
                }
                // Library option (smaller, below the main button)
                Button(action: { showingPhotosPicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 13))
                        Text("Choose from Photos")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.top, 10)
                }
            }
        }
        // Confirmation dialog for re-scan
        .confirmationDialog("Change Scan", isPresented: $showingImageSourcePicker) {
            if VNDocumentCameraViewController.isSupported {
                Button("Scan New Document") { showingScanner = true }
            }
            Button("Choose from Photos") { showingPhotosPicker = true }
            Button("Remove Scan", role: .destructive) {
                documentImage = nil
                documentData = nil
            }
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DOCUMENT NAME")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.2)
            TextField("e.g. CDL License", text: $name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(14)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(name.isEmpty ? AppTheme.Colors.danger.opacity(0.4) : Color.white.opacity(0.07),
                                lineWidth: 1)
                )
                .autocorrectionDisabled()
        }
    }

    // MARK: - Type Selector (grid)

    private var typeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TYPE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(DocumentType.allCases, id: \.self) { type in
                    let selected = documentType == type
                    Button(action: { documentType = type }) {
                        VStack(spacing: 5) {
                            Image(systemName: type.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(selected ? .white : type.color)
                            Text(type.shortLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(selected ? .white : AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selected ? type.color : type.color.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selected ? type.color : type.color.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Expiry Section

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXPIRATION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.2)

            Toggle(isOn: $hasExpiration) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundColor(AppTheme.Colors.warning)
                    Text("This document expires")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
            }
            .tint(AppTheme.Colors.accent)
            .padding(14)
            .background(AppTheme.Colors.backgroundCard)
            .cornerRadius(12)

            if hasExpiration {
                DatePicker(
                    "Expires on",
                    selection: $expirationDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .font(.system(size: 15))
                .foregroundColor(.white)
                .tint(AppTheme.Colors.accent)
                .padding(14)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Reminder Row

    private var reminderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 18))
                .foregroundColor(reminderEnabled ? AppTheme.Colors.accent : AppTheme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Expiry Reminder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                if hasExpiration {
                    Text("\(reminderDaysBefore) days before expiry")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                } else {
                    Text("Set an expiration date first")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $reminderEnabled)
                .tint(AppTheme.Colors.accent)
                .disabled(!hasExpiration)
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(12)
    }

    // MARK: - Notes Field

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .kerning(1.2)
            TextEditor(text: $notes)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .frame(height: 80)
                .padding(10)
                .background(AppTheme.Colors.backgroundCard)
                .cornerRadius(12)
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: saveDocument) {
            HStack(spacing: 10) {
                Image(systemName: documentImage != nil ? "lock.doc.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(documentImage != nil ? "Save Scanned Document" : "Save Document")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(canSave ? AppTheme.Colors.background : AppTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(canSave ? AppTheme.Colors.accent : AppTheme.Colors.backgroundCard)
            .cornerRadius(16)
        }
        .disabled(!canSave)
    }

    // MARK: - Save Action

    private func saveDocument() {
        let document = TruckDocument(
            name: name,
            documentType: documentType,
            issueDate: issueDate,
            expirationDate: hasExpiration ? expirationDate : nil,
            notes: notes,
            reminderEnabled: reminderEnabled && hasExpiration,
            reminderDaysBefore: reminderDaysBefore
        )
        document.documentData = documentData
        modelContext.insert(document)
        dismiss()
    }
}

// MARK: - DocumentType helpers for the new UI

private extension DocumentType {
    var icon: String {
        switch self {
        case .registration: return "doc.text.fill"
        case .insurance:    return "shield.fill"
        case .permit:       return "star.circle.fill"
        case .inspection:   return "checkmark.shield.fill"
        case .license:      return "creditcard.fill"
        case .medical:      return "cross.case.fill"
        case .other:        return "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .registration: return Color(hex: "#f59e0b")
        case .insurance:    return AppTheme.Colors.success
        case .permit:       return Color(hex: "#7c3aed")
        case .inspection:   return AppTheme.Colors.cta
        case .license:      return AppTheme.Colors.accent
        case .medical:      return AppTheme.Colors.danger
        case .other:        return AppTheme.Colors.textSecondary
        }
    }

    var shortLabel: String {
        switch self {
        case .registration: return "Registration"
        case .insurance:    return "Insurance"
        case .permit:       return "Permit"
        case .inspection:   return "Inspection"
        case .license:      return "License"
        case .medical:      return "Medical"
        case .other:        return "Other"
        }
    }
}

#Preview {
    AddDocumentView()
        .modelContainer(for: TruckDocument.self, inMemory: true)
}
