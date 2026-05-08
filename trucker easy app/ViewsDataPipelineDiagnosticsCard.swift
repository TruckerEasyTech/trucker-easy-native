import SwiftUI
import CoreLocation

struct DataPipelineDiagnosticsCard: View {
    let locationManager: LocationManager
    let fleetTelemetryService: FleetTelemetryService
    let jurisdictionPolicyService: JurisdictionPolicyService
    let operationalFeedService: OperationalFeedService
    let onClose: () -> Void

    // GPS is "live" if the last fix is no older than 5 seconds
    private var gpsIsLive: Bool {
        guard let loc = locationManager.currentLocation else { return false }
        return Date().timeIntervalSince(loc.timestamp) < 5
    }

    private var gpsDetails: String {
        guard let loc = locationManager.currentLocation else { return "No signal" }
        let acc = Int(loc.horizontalAccuracy)
        let spd = max(0, loc.speed * 2.23694)
        if spd > 0.5 {
            return String(format: "%.0f mph · ±%dm", spd, acc)
        }
        return String(format: "±%dm accuracy", acc)
    }

    // Policy is healthy when activePolicy is set and there is no outstanding error
    private var policyIsHealthy: Bool {
        jurisdictionPolicyService.activePolicy != nil && jurisdictionPolicyService.lastError == nil
    }

    private var policyDetails: String {
        if let src = jurisdictionPolicyService.lastSuccessfulSource {
            return src
        }
        if let err = jurisdictionPolicyService.lastError {
            return err
        }
        return "Awaiting location"
    }

    // Mapbox routing/renderer token configured in Info.plist
    private var mapboxRoutingConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tomTomRoutingConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "TomTomAPIKey") as? String ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mapboxConfigured: Bool {
        mapboxRoutingConfigured
    }

    private var tomTomSDKReady: Bool {
        UserDefaults.standard.bool(forKey: "tomtom_sdk_ready")
    }

    private var routingHealthy: Bool {
        mapboxConfigured || tomTomRoutingConfigured || tomTomSDKReady
    }

    private var routingDetails: String {
        let mapboxApi = mapboxRoutingConfigured ? "Mapbox: ok" : "Mapbox: missing"
        let tomTomSDK = tomTomSDKReady ? "TomTom SDK: ok" : "TomTom SDK: off"
        let tomTomApi = tomTomRoutingConfigured ? "TomTom API: ok" : "TomTom API: missing"
        let provider = RoutingService.shared.lastProvider.rawValue
        return "\(provider) · \(tomTomSDK) · \(mapboxApi) · \(tomTomApi)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Data Diagnostics", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }

            statusRow(name: "GPS",     isHealthy: gpsIsLive,           details: gpsDetails)
            statusRow(name: "Policy",  isHealthy: policyIsHealthy,     details: policyDetails)
            statusRow(name: "Routing", isHealthy: routingHealthy,      details: routingDetails)
        }
        .padding(12)
        .background(AppTheme.Colors.backgroundCard.opacity(0.95))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusRow(name: String, isHealthy: Bool, details: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isHealthy ? AppTheme.Colors.success : AppTheme.Colors.warning)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(details)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
