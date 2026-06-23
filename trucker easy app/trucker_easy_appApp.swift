import SwiftUI
import SwiftData
import UserNotifications
import Foundation

#if DEBUG
import OSLog

private func validateBuildConfig() {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TruckerEasy", category: "BuildConfig")
    let mapboxToken = Bundle.main.infoDictionary?["MBXAccessToken"] as? String
    let listRaw = Bundle.main.object(forInfoDictionaryKey: "ValhallaServerURLs") as? String ?? ""
    let parts = listRaw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "||", with: "//") }
        .filter { !$0.isEmpty && !$0.contains("$(") }
    let single = (Bundle.main.object(forInfoDictionaryKey: "ValhallaServerURL") as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "||", with: "//")
    let valhallaPreview = (parts.first ?? (single.isEmpty ? nil : single)).map { String($0.prefix(48)) } ?? "MISSING"

    let mapboxPreview = mapboxToken.map { String($0.prefix(10)) } ?? "MISSING"

    logger.debug("🗺️ Mapbox token (prefix): \(mapboxPreview, privacy: .public)")
    logger.debug("🛣️ Valhalla URL (prefix): \(valhallaPreview, privacy: .public)")

    if mapboxToken?.contains("$(") == true || valhallaPreview.contains("$(") {
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

    /// SwiftData store — created synchronously in `init()` so the first frame is never stuck on
    /// an async `.task` that might not run or might leave `modelContainer == nil` (blank / “Carregando…” forever).
    private let modelContainer: ModelContainer

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
        #if DEBUG
        print("[SwiftData] ⚠️ Schema migration failed — recreating store")
        #endif
        try? FileManager.default.removeItem(at: storeURL)
        let freshConfig = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [freshConfig])
    }

    /// Never returns `nil` — avoids infinite launch spinner if async bootstrap never completes.
    nonisolated private static func makeModelContainerAtLaunch() -> ModelContainer {
        do {
            return try buildModelContainer()
        } catch {
            #if DEBUG
            print("[SwiftData] ⚠️ Persistent store error: \(error.localizedDescription)")
            #endif
            let schema = appSchema()
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(for: schema, configurations: [memConfig])
                #if DEBUG
                print("[SwiftData] ⚠️ Using in-memory store (persistent unavailable)")
                #endif
                return container
            } catch {
                fatalError("SwiftData could not create ModelContainer: \(error)")
            }
        }
    }

    /// Self-heal do launch: se o tile store offline do Mapbox passou de um limite, o load dele no
    /// startup TRAVA o app ("não abre" / tela preta). Aqui apagamos SÓ o diretório de cache de mapas
    /// (`Application Support/.mapbox`) ANTES de o Mapbox abrir o DB. NÃO toca SwiftData — viagens,
    /// HOS, combustível, documentos ficam INTACTOS (ficam no store do SwiftData, outro diretório).
    /// O cache de mapas re-popula sozinho por rota. Roda 1x no boot, antes de qualquer init do Mapbox.
    nonisolated private static func purgeOversizedMapboxCacheAtLaunch() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let mapboxDir = appSupport.appendingPathComponent(".mapbox", isDirectory: true)
        guard fm.fileExists(atPath: mapboxDir.path) else { LaunchTrace.mark("selfheal: no .mapbox dir"); return }
        let limit: UInt64 = 150 * 1024 * 1024   // 150 MB — só apaga quando REALMENTE inchado
        let bytes = directorySizeBytes(mapboxDir)
        LaunchTrace.mark("selfheal: .mapbox = \(bytes / 1024 / 1024) MB")
        guard bytes > limit else { LaunchTrace.mark("selfheal: under limit, keep"); return }
        LaunchTrace.mark("selfheal: renaming oversized cache")
        // CRÍTICO: NÃO apagar 344 MB em linha aqui — removeItem recursivo síncrono na main thread
        // durante o launch trava o app (o próprio bug que queremos matar). Em vez disso RENOMEIA
        // (operação O(1), instantânea, mesmo volume) → o Mapbox vê o dir sumido e recria limpo;
        // o lixo renomeado é apagado DEPOIS, numa thread de background.
        let trash = appSupport.appendingPathComponent(".mapbox_trash", isDirectory: true)
        try? fm.removeItem(at: trash)   // remove um lixo anterior, se sobrou
        do {
            try fm.moveItem(at: mapboxDir, to: trash)
            DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: trash) }
        } catch {
            try? fm.removeItem(at: mapboxDir)   // fallback se o rename falhar
        }
        #if DEBUG
        print("[MapboxCache] tile store inchado (\(bytes / 1024 / 1024) MB) > 150 MB — renomeado+purgado no launch (self-heal, sem travar). SwiftData intacto.")
        #endif
    }

    nonisolated private static func directorySizeBytes(_ url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey],
                                     options: [.skipsHiddenFiles], errorHandler: nil) else { return 0 }
        var total: UInt64 = 0
        for case let f as URL in en {
            if let sz = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += UInt64(sz) }
        }
        return total
    }

    init() {
        LaunchTrace.reset()
        LaunchTrace.mark("init.start")
        // PRIMEIRA coisa no boot: auto-cura do cache de mapas inchado (antes de tocar no Mapbox).
        Self.purgeOversizedMapboxCacheAtLaunch()
        LaunchTrace.mark("init.afterPurge")
        #if DEBUG
        validateBuildConfig()
        #if arch(arm64)
        // Vigia de congelamento: se a main thread travar >5s, imprime o backtrace dela.
        MainThreadWatchdog.start()
        #endif
        #endif
        AppAccessPolicy.applyTestingDefaultsIfNeeded()
        MapProviderConfig.configureIfAvailable()
        _ = MapProviderConfig.verifyProviderHealth()
        LaunchTrace.mark("init.afterMapboxConfig")
        #if DEBUG
        if AppAccessPolicy.unlockAllFeaturesForTesting {
            print("[AppAccess] 🧪 Testing mode ON — Premium unlocked, Valhalla truck routing only")
        }
        print("[Routing] Valhalla-only for truck routes: \(AppAccessPolicy.enforceTruckOnlyRouting ? "ON" : "OFF") — no MapKit/OSRM fallback on failure")
        #endif
        modelContainer = Self.makeModelContainerAtLaunch()
        LaunchTrace.mark("init.afterModelContainer")
        FuelPriceService.shared.bootstrap()
        LaunchTrace.mark("init.afterFuelBootstrap")
        // MapKit tile cache uses the OS system cache (separate); this governs API responses.
        URLCache.shared = URLCache(
            memoryCapacity: 10 * 1024 * 1024,
            diskCapacity: 40 * 1024 * 1024,
            directory: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .modelContainer(modelContainer)
                .preferredColorScheme(.dark)
        }
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
        #if DEBUG
        print("APNs Device Token: \(tokenString)")
        #endif
        UserDefaults.standard.set(tokenString, forKey: "apns_device_token")
        // Register token with Supabase so push notifications can be targeted to this device
        Task {
            await SupabaseClient.shared.registerDeviceToken(tokenString)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
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

        if AppAccessPolicy.driverDispatchEnabled,
           let load = DispatchService.shared.loadFromNotificationPayload(userInfo) {
            DispatchService.shared.handleIncomingLoad(load)
        }
        completionHandler()
    }

    // MARK: - Remote push notification received while app is active
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if AppAccessPolicy.driverDispatchEnabled,
           let load = DispatchService.shared.loadFromNotificationPayload(userInfo) {
            DispatchService.shared.handleIncomingLoad(load)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
}
