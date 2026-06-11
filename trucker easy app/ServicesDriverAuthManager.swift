// ServicesDriverAuthManager.swift — Supabase Auth session for drivers (fleet dispatch).

import Foundation
import Observation

@MainActor
@Observable
final class DriverAuthManager {
    static let shared = DriverAuthManager()

    private(set) var isSignedIn = false
    private(set) var driverId: String?
    private(set) var email: String?
    private(set) var lastError: String?
    private(set) var pendingLoadCount: Int?
    private(set) var isBusy = false

    private init() {
        syncFromClient()
    }

    func syncFromClient() {
        isSignedIn = SupabaseClient.shared.isAuthenticated
        driverId = SupabaseClient.shared.currentDriverId
        email = UserDefaults.standard.string(forKey: "supabase_driver_email")
    }

    @discardableResult
    func signIn(email: String, password: String, fullName: String? = nil) async -> Bool {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let auth = try await SupabaseClient.shared.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                                              password: password)
            UserDefaults.standard.set(auth.user?.email ?? email, forKey: "supabase_driver_email")
            try await SupabaseClient.shared.ensureDriverProfile(
                email: auth.user?.email ?? email,
                fullName: fullName?.isEmpty == false ? fullName : driverNameFromDefaults()
            )
            syncFromClient()
            _ = await refreshPendingLoads(pushFirstToHorizon: true)
            return true
        } catch {
            lastError = error.localizedDescription
            syncFromClient()
            return false
        }
    }

    @discardableResult
    func signUp(email: String, password: String, fullName: String) async -> Bool {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let auth = try await SupabaseClient.shared.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            UserDefaults.standard.set(auth.user?.email ?? email, forKey: "supabase_driver_email")
            try await SupabaseClient.shared.ensureDriverProfile(
                email: auth.user?.email ?? email,
                fullName: fullName.isEmpty ? driverNameFromDefaults() : fullName
            )
            syncFromClient()
            return true
        } catch {
            lastError = error.localizedDescription
            syncFromClient()
            return false
        }
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await SupabaseClient.shared.signOut()
        } catch {
            #if DEBUG
            print("DriverAuthManager: signOut — \(error.localizedDescription)")
            #endif
        }
        UserDefaults.standard.removeObject(forKey: "supabase_driver_email")
        pendingLoadCount = nil
        lastError = nil
        syncFromClient()
    }

    /// Fetches pending loads; optionally surfaces the newest on the map tab.
    @discardableResult
    func refreshPendingLoads(pushFirstToHorizon: Bool = false) async -> Int? {
        guard isSignedIn else {
            pendingLoadCount = nil
            return nil
        }
        do {
            let records = try await SupabaseClient.shared.fetchPendingLoads()
            pendingLoadCount = records.count
            if pushFirstToHorizon, let first = records.first {
                let load = DispatchedLoad(
                    id: first.id,
                    driverId: first.driver_id ?? driverId ?? "",
                    loadNumber: first.load_number,
                    originAddress: first.origin_address,
                    destinationAddress: first.destination_address,
                    destinationLatitude: first.destination_lat,
                    destinationLongitude: first.destination_lng,
                    pickupTime: nil,
                    deliveryTime: nil,
                    commodity: first.commodity,
                    weightLbs: first.weight_lbs,
                    specialInstructions: first.special_instructions,
                    status: .pending,
                    companyId: first.company_id,
                    companyName: first.company_name,
                    valorFrete: first.valor_frete,
                    precoDieselEia: first.preco_diesel_eia
                )
                DispatchService.shared.handleIncomingLoad(load)
            }
            return records.count
        } catch {
            lastError = error.localizedDescription
            pendingLoadCount = nil
            return nil
        }
    }

    private func driverNameFromDefaults() -> String? {
        let name = UserDefaults.standard.string(forKey: "driverName") ?? ""
        return name.isEmpty || name == "Driver" ? nil : name
    }
}
