// ViewsDriverFleetAccountSheet.swift — Sign in / dispatch test for fleet integration.

import SwiftUI

struct DriverFleetAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var auth: DriverAuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var isRegisterMode = false
    @State private var copiedDriverId = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        introCard

                        if auth.isSignedIn {
                            signedInCard
                        } else {
                            authForm
                        }

                        dispatcherHintCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Fleet account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            auth.syncFromClient()
            if let saved = auth.email, email.isEmpty { email = saved }
            if fullName.isEmpty {
                let local = UserDefaults.standard.string(forKey: "driverName") ?? ""
                if !local.isEmpty, local != "Driver" { fullName = local }
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Same account as truckereasy.com dispatch", systemImage: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.Colors.accent)
            Text("Sign in with the email your fleet registered. Pending loads from the dispatcher portal appear on My Horizon.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.backgroundSecond)
        .cornerRadius(12)
    }

    private var signedInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.Colors.success)
                Text("Signed in")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            if let mail = auth.email {
                Text(mail)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            if let id = auth.driverId {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Driver ID (give this to your dispatcher)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    Text(id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                    Button(copiedDriverId ? "Copied" : "Copy driver ID") {
                        UIPasteboard.general.string = id
                        copiedDriverId = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.accent)
                }
            }
            if let count = auth.pendingLoadCount {
                Text(count == 0 ? "No pending loads" : "\(count) pending load(s)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(count > 0 ? AppTheme.Colors.warning : AppTheme.Colors.textSecondary)
            }
            Button {
                Task { await auth.refreshPendingLoads(pushFirstToHorizon: true) }
            } label: {
                HStack {
                    Spacer()
                    if auth.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Refresh loads on map")
                            .font(.system(size: 15, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(AppTheme.Colors.accent)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .disabled(auth.isBusy)

            Button(role: .destructive) {
                Task {
                    await auth.signOut()
                }
            } label: {
                Text("Sign out of fleet account")
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundSecond)
        .cornerRadius(12)
    }

    private var authForm: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $isRegisterMode) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)

            if isRegisterMode {
                TextField("Full name", text: $fullName)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .fleetFieldStyle()
            }

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .fleetFieldStyle()

            SecureField("Password", text: $password)
                .textContentType(isRegisterMode ? .newPassword : .password)
                .fleetFieldStyle()

            if let err = auth.lastError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.danger)
            }

            Button {
                Task {
                    let ok: Bool
                    if isRegisterMode {
                        ok = await auth.signUp(email: email, password: password, fullName: fullName)
                    } else {
                        ok = await auth.signIn(email: email, password: password, fullName: fullName.nilIfEmpty)
                    }
                    if ok { dismiss() }
                }
            } label: {
                HStack {
                    Spacer()
                    if auth.isBusy {
                        ProgressView().tint(.black)
                    } else {
                        Text(isRegisterMode ? "Create & sign in" : "Sign in")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(AppTheme.Colors.accent)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .disabled(auth.isBusy || email.isEmpty || password.count < 6)
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundSecond)
        .cornerRadius(12)
    }

    private var dispatcherHintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("For dispatchers (truckereasy.com)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            Text("When creating a load, set driver_id to the driver's UUID shown above after they sign in. Deep link format: truckereasy://dispatch?loadId=…&lat=…&lng=…&address=…")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(14)
        .background(AppTheme.Colors.backgroundCard)
        .cornerRadius(12)
    }
}

private extension View {
    func fleetFieldStyle() -> some View {
        self
            .padding(12)
            .background(AppTheme.Colors.backgroundInput)
            .cornerRadius(10)
            .foregroundColor(.white)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
