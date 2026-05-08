import SwiftUI
import SwiftData
import UserNotifications
import Foundation

#if DEBUG
import OSLog

private func validateBuildConfig() {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruckerEasy", category: "BuildConfig")
    let mapboxToken = Bundle.main.infoDictionary?["MBXAccessToken"] as? String
    let valhallaURL = Bundle.main.infoDictionary?["ValhallaServerURL"] as? String

    let mapboxPreview = mapboxToken.map { String($0.prefix(10)) } ?? "MISSING"
    let valhallaPreview = valhallaURL.map { String($0.prefix(48)) } ?? "MISSING"

    logger.debug("🗺️ Mapbox token (prefix): \(mapboxPreview, privacy: .public)")
    logger.debug("🛣️ Valhalla URL (prefix): \(valhallaPreview, privacy: .public)")

    if mapboxToken?.contains("$(") == true || valhallaURL?.contains("$(") == true {
        logger.warning("⚠️ Unresolved build variables in Info.plist — check Config/TruckerEasy.secrets.xcconfig and target Base Configuration.")
    }
}
#endif

extension Notification.Name {
    static let medicationReminderFired = Notification.Name("medicationReminderFired")
}

@main
struct trucker_easy_appApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var modelContainer: ModelContainer?
    @State private var didStartBootstrap = false

    // #region agent log (DEBUG only — path under app Caches, never a repo absolute path)
    private static func agentNDJSONLog(hypothesisId: String, location: String, message: String, data: [String: String] = [:]) {
        #if DEBUG
        let logURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("debug-bootstrap-2417a5.ndjson", isDirectory: false)
        let dict: [String: Any] = [
            "sessionId": "2417a5",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "data": data,
            "runId": "bootstrap-main",
        ]
        guard JSONSerialization.isValidJSONObject(dict),
              let json = try? JSONSerialization.data(withJSONObject: dict),
              var line = String(data: json, encoding: .utf8) else { return }
        line.append("\n")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let d = line.data(using: .utf8) { try? handle.write(contentsOf: d) }
        #endif
    }
    // #endregion

    private func initializeRoutingRuntime() {
        print("[Routing] ℹ️ Truck routing: Valhalla (truck-aware) + MapKit/OSRM (fallback)")
    }

    nonisolated private static func appSchema() -> Schema {
        Schema([
            Trip.self, FuelPurchase.self, Expense.self, IFTAReport.self,
            TruckDocument.self, GeofenceRegion.self, ChatMessage.self,
            ChatChannel.self, CommunityPost.self, PostComment.self, WellnessLog.self,
            Medication.self,
        ])
    }

    nonisolated private static func buildModelContainer() throws -> ModelContainer {
        let schema = appSchema()
        // Ensure Application Support directory exists before SwiftData tries to write the store.
        // On first launch the OS has not yet created this directory; without it SwiftData
        // emits a large cascade of CoreData error logs before its own recovery kicks in.
        let supportDir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        // Try persistent store first; if migration fails (schema changed), wipe and recreate
        let storeURL = supportDir.appending(path: "trucker_easy.store")
        let persistentConfig = ModelConfiguration(schema: schema, url: storeURL)
        if let container = try? ModelContainer(for: schema, configurations: [persistentConfig]) {
            return container
        }
        // Store incompatible with current schema — delete and start fresh
        print("[SwiftData] ⚠️ Schema migration failed — recreating store")
        try? FileManager.default.removeItem(at: storeURL)
        let freshConfig = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [freshConfig])
    }

    @MainActor
    private func bootstrapIfNeeded() async {
        guard !didStartBootstrap else { return }
        didStartBootstrap = true

        #if DEBUG
        validateBuildConfig()
        #endif

        // #region agent log
        Self.agentNDJSONLog(hypothesisId: "H1", location: "trucker_easy_appApp.swift:bootstrapIfNeeded", message: "bootstrap start (main-actor container)", data: [:])
        print("[DBG][BOOT][H-app-1] bootstrap start")
        // #endregion

        // Critical: configure map provider synchronously (fast, no network)
        MapProviderConfig.configureIfAvailable()
        _ = MapProviderConfig.verifyProviderHealth()
        initializeRoutingRuntime()

        // H1: SwiftData ModelContainer must be created on the main actor — Task.detached could hang or fail silently with try?.
        let schema = Self.appSchema()
        do {
            modelContainer = try Self.buildModelContainer()
            // #region agent log
            Self.agentNDJSONLog(hypothesisId: "H1", location: "trucker_easy_appApp.swift:bootstrapIfNeeded", message: "persistent ModelContainer ready", data: [:])
            print("[DBG][BOOT][H-app-1] persistent ModelContainer ready")
            // #endregion
        } catch {
            print("[SwiftData] ⚠️ Persistent store error: \(error.localizedDescription)")
            // #region agent log
            Self.agentNDJSONLog(hypothesisId: "H2", location: "trucker_easy_appApp.swift:bootstrapIfNeeded", message: "persistent failed", data: ["error": error.localizedDescription])
            // #endregion
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [memConfig])
                print("[SwiftData] ⚠️ Using in-memory store (persistent unavailable)")
                // #region agent log
                Self.agentNDJSONLog(hypothesisId: "H2", location: "trucker_easy_appApp.swift:bootstrapIfNeeded", message: "in-memory fallback ok", data: [:])
                print("[DBG][BOOT][H-app-2] fallback in-memory ModelContainer")
                // #endregion
            } catch {
                print("[SwiftData] ❌ In-memory ModelContainer failed: \(error.localizedDescription)")
                // #region agent log
                Self.agentNDJSONLog(hypothesisId: "H2", location: "trucker_easy_appApp.swift:bootstrapIfNeeded", message: "in-memory failed — UI stuck on loading", data: ["error": error.localizedDescription])
                // #endregion
                modelContainer = nil
            }
        }

        // Non-critical services — run after UI is unblocked
        FuelPriceService.shared.bootstrap()

        // Configure shared URL cache — hard cap to prevent runaway disk growth on long trips.
        // MapKit tile cache uses the OS system cache (separate); this governs API responses.
        URLCache.shared = URLCache(
            memoryCapacity: 10 * 1024 * 1024,  // 10 MB RAM for API responses
            diskCapacity:   40 * 1024 * 1024,  // 40 MB disk (route JSON, weather, fuel prices)
            directory: nil
        )
        // #region agent log
        Self.agentNDJSONLog(hypothesisId: "H3", location: "trucker_easy_appApp.swift:bootstrapIfNeeded", message: "bootstrap done", data: ["hasContainer": modelContainer != nil ? "true" : "false"])
        print("[DBG][BOOT][H-app-1] bootstrap done")
        // #endregion
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer {
                    AppEntryView()
                        .modelContainer(modelContainer)
                        .preferredColorScheme(.dark)
                } else {
                    StartupLoadingView()
                        .transition(.opacity)
                }
            }
            .task {
                await bootstrapIfNeeded()
            }
        }
    }
}

private struct StartupLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "#ff9f3f"))
            Text("Carregando…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - App Delegate for Push Notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        return true
    }

    // MARK: - Remote notification registration
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to hex string
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs Device Token: \(tokenString)")
        UserDefaults.standard.set(tokenString, forKey: "apns_device_token")
        // Register token with Supabase so push notifications can be targeted to this device
        Task {
            await SupabaseClient.shared.registerDeviceToken(tokenString)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Foreground notification display
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.categoryIdentifier == "MEDICATION_DUE"
            || notification.request.content.userInfo["medicationId"] != nil {
            NotificationCenter.default.post(
                name: .medicationReminderFired,
                object: nil,
                userInfo: notification.request.content.userInfo
            )
        }
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - Notification tap handling
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        if userInfo["medicationId"] != nil {
            NotificationCenter.default.post(name: .medicationReminderFired, object: nil, userInfo: userInfo)
        }

        // Check if it's a dispatched load notification
        if let load = DispatchService.shared.loadFromNotificationPayload(userInfo) {
            DispatchService.shared.handleIncomingLoad(load)
        }
        completionHandler()
    }

    // MARK: - Remote push notification received while app is active
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let load = DispatchService.shared.loadFromNotificationPayload(userInfo) {
            DispatchService.shared.handleIncomingLoad(load)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
}
