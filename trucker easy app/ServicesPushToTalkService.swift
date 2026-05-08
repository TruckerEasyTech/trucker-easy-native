// © 2024–2025 TruckerEasy LLC. All rights reserved.
// Push-to-Talk (CB Radio / Channel 19) — Agora RTC backend

import Foundation
import AVFoundation
import Observation

#if canImport(AgoraRtcKit)
import AgoraRtcKit
#endif

// MARK: - Models

enum PTTConnectionState {
    case disconnected, connecting, connected, error(String)

    var label: String {
        switch self {
        case .disconnected:   return "Off Air"
        case .connecting:     return "Connecting…"
        case .connected:      return "On Air"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    var isOnAir: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum PTTChannel: String, CaseIterable, Identifiable {
    case national  = "All Truckers"
    case i10       = "I-10 Corridor"
    case i40       = "I-40 Southwest"
    case i70       = "I-70 Midwest"
    case i80       = "I-80 Corridor"
    case i90       = "I-90 Northern"
    case i95       = "I-95 East"
    case southeast = "Southeast"
    case northwest = "Northwest"

    var id: String { rawValue }

    /// Channel ID used in Agora (safe lowercase ASCII)
    var agoraChannelId: String {
        "te_\(rawValue.lowercased().replacingOccurrences(of: " ", with: "_").filter { $0.isLetter || $0.isNumber || $0 == "_" })"
    }

    var icon: String { "antenna.radiowaves.left.and.right" }

    var colorHex: String {
        switch self {
        case .national:  return "#ff6b00"
        case .i10:       return "#00d4ff"
        case .i40:       return "#f59e0b"
        case .i70:       return "#10b981"
        case .i80:       return "#6366f1"
        case .i90:       return "#a78bfa"
        case .i95:       return "#ef4444"
        case .southeast: return "#ec4899"
        case .northwest: return "#34d399"
        }
    }
}

struct PTTSpeaker: Identifiable, Equatable {
    let id: UInt        // Agora UID
    let name: String
    var isTalking: Bool
    var signalStrength: Int   // 0–9
}

struct PTTTransmission: Identifiable {
    let id = UUID()
    let speakerName: String
    let channel: PTTChannel
    let durationSeconds: Int
    let timestamp = Date()
}

// MARK: - Push-to-Talk Service

@Observable
final class PushToTalkService: NSObject {

    static let shared = PushToTalkService()

    // MARK: Published state
    private(set) var connectionState: PTTConnectionState = .disconnected
    private(set) var currentChannel: PTTChannel = .national
    private(set) var isTalking: Bool = false
    private(set) var activeSpeakers: [PTTSpeaker] = []
    private(set) var recentTransmissions: [PTTTransmission] = []
    private(set) var listenerCount: Int = 0

    // MARK: Private
    private var talkStartTime: Date?

    #if canImport(AgoraRtcKit)
    private var agoraKit: AgoraRtcEngineKit?
    private var localUid: UInt = 0
    #endif

    private var agoraAppId: String {
        (Bundle.main.object(forInfoDictionaryKey: "AgoraAppID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func join(channel: PTTChannel) {
        guard !connectionState.isOnAir else {
            // Switch channel
            leave()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.join(channel: channel) }
            return
        }
        currentChannel = channel
        connectionState = .connecting

        #if canImport(AgoraRtcKit)
        guard !agoraAppId.isEmpty else {
            connectionState = .error("AgoraAppID missing in Info.plist")
            return
        }
        setupAgora()
        let code = agoraKit?.joinChannel(
            byToken: nil,
            channelId: channel.agoraChannelId,
            info: nil,
            uid: 0
        ) ?? -1
        if code != 0 {
            connectionState = .error("Join failed (\(code))")
        }
        // Connection success handled in delegate
        return
        #else
        connectionState = .error("Agora SDK not linked in this build")
        #endif
    }

    func leave() {
        stopTransmitting()
        activeSpeakers = []
        listenerCount = 0
        connectionState = .disconnected

        #if canImport(AgoraRtcKit)
        agoraKit?.leaveChannel()
        #endif
    }

    /// Call when user presses the PTT button.
    func startTransmitting() {
        guard connectionState.isOnAir, !isTalking else { return }
        isTalking = true
        talkStartTime = Date()

        #if canImport(AgoraRtcKit)
        agoraKit?.muteLocalAudioStream(false)
        #endif
    }

    /// Call when user releases the PTT button.
    func stopTransmitting() {
        guard isTalking else { return }
        isTalking = false

        let duration: Int
        if let start = talkStartTime {
            duration = max(1, Int(Date().timeIntervalSince(start)))
        } else {
            duration = 1
        }
        talkStartTime = nil

        #if canImport(AgoraRtcKit)
        agoraKit?.muteLocalAudioStream(true)
        #endif

        let tx = PTTTransmission(speakerName: "You", channel: currentChannel, durationSeconds: duration)
        recentTransmissions.insert(tx, at: 0)
        if recentTransmissions.count > 15 { recentTransmissions.removeLast() }
    }

    // MARK: - Agora setup

    #if canImport(AgoraRtcKit)
    private func setupAgora() {
        guard agoraKit == nil else { return }
        let config = AgoraRtcEngineConfig()
        config.appId = agoraAppId
        config.channelProfile = .liveBroadcasting
        agoraKit = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
        agoraKit?.setClientRole(.broadcaster)
        // Mute local until PTT button is held
        agoraKit?.muteLocalAudioStream(true)
        // Audio profile for voice (not music)
        agoraKit?.setAudioProfile(.speechStandard)
        agoraKit?.enableAudio()
    }
    #endif

}

// MARK: - Agora Delegate

#if canImport(AgoraRtcKit)
extension PushToTalkService: AgoraRtcEngineDelegate {

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinChannel channel: String, withUid uid: UInt, elapsed: Int) {
        localUid = uid
        connectionState = .connected
        // Start muted; user must hold PTT
        engine.muteLocalAudioStream(true)
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didLeaveChannelWith stats: AgoraChannelStats) {
        connectionState = .disconnected
        activeSpeakers = []
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        connectionState = .error("Code \(errorCode.rawValue)")
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        listenerCount += 1
        let speaker = PTTSpeaker(id: uid, name: "Driver_\(uid % 1000)", isTalking: false, signalStrength: 7)
        activeSpeakers.append(speaker)
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        listenerCount = max(0, listenerCount - 1)
        activeSpeakers.removeAll { $0.id == uid }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, reportAudioVolumeIndicationOfSpeakers speakers: [AgoraRtcAudioVolumeInfo], totalVolume: Int) {
        for info in speakers {
            if let idx = activeSpeakers.firstIndex(where: { $0.id == info.uid }) {
                activeSpeakers[idx].isTalking = info.volume > 10
            }
        }
    }
}
#endif
