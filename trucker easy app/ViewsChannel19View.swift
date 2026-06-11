// © 2024–2026 TruckerEasy LLC. All rights reserved.
// Channel 19 — Push-to-Talk CB Radio for Truckers

import SwiftUI

// MARK: - Channel 19 View

struct Channel19View: View {
    @State private var ptt = PushToTalkService.shared
    @State private var showingChannelPicker = false
    @State private var pttScale: CGFloat = 1.0
    @State private var wavePhase: Double = 0

    private let orange = Color(hex: "#ff6b00")
    private let navy   = Color(hex: "#0d1b2a")
    private let cyan   = Color(hex: "#00d4ff")
    private var channelColor: Color { Color(hex: ptt.currentChannel.colorHex) }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "#05080f"), Color(hex: "#080f1a"), Color(hex: "#0a1220")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.06))
                    .padding(.bottom, 8)

                if ptt.connectionState.isOnAir {
                    activeSpeakersSection
                }

                Spacer()

                // Central PTT button area
                pttButtonArea

                Spacer()

                // Recent transmissions
                if !ptt.recentTransmissions.isEmpty {
                    recentSection
                }

                Spacer().frame(height: 16)
            }
        }
        .onAppear {
            // Start wave animation loop
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
        }
        .sheet(isPresented: $showingChannelPicker) {
            ChannelPickerSheet(ptt: ptt)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Signal / status
            HStack(spacing: 5) {
                signalBars
                VStack(alignment: .leading, spacing: 1) {
                    Text(ptt.connectionState.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ptt.connectionState.isOnAir ? Color(hex: "#22d474") : Color(hex: "#9ca3af"))
                    if ptt.connectionState.isOnAir {
                        Text("\(ptt.listenerCount) listeners")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }

            Spacer()

            // Channel selector button
            Button(action: { showingChannelPicker = true }) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(channelColor)
                        .frame(width: 7, height: 7)
                    Text(ptt.currentChannel.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(channelColor.opacity(0.35), lineWidth: 1)
                )
            }

            // Connect / Disconnect
            Button(action: {
                if ptt.connectionState.isOnAir {
                    ptt.leave()
                } else {
                    ptt.join(channel: ptt.currentChannel)
                }
            }) {
                Image(systemName: ptt.connectionState.isOnAir ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(ptt.connectionState.isOnAir ? Color(hex: "#ef4444") : Color(hex: "#22d474"))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .cornerRadius(18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Signal Bars

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1..<5) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(ptt.connectionState.isOnAir
                          ? Color(hex: "#22d474")
                          : Color.white.opacity(0.15))
                    .frame(width: 3, height: CGFloat(i) * 4)
            }
        }
    }

    // MARK: - Active Speakers

    private var activeSpeakersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#22d474"))
                    .frame(width: 6, height: 6)
                    .opacity(ptt.activeSpeakers.isEmpty ? 0 : 1)
                Text(ptt.activeSpeakers.isEmpty ? "Channel clear" : "Live now")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ptt.activeSpeakers.isEmpty
                                     ? Color.white.opacity(0.3)
                                     : Color(hex: "#22d474"))
                    .kerning(1)
            }
            .padding(.horizontal, 16)

            if !ptt.activeSpeakers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ptt.activeSpeakers) { speaker in
                            ActiveSpeakerChip(speaker: speaker, channelColor: channelColor)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - PTT Button Area

    private var pttButtonArea: some View {
        VStack(spacing: 20) {
            // Animated sound waves (visible when talking)
            ZStack {
                if ptt.isTalking {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(channelColor.opacity(0.3 - Double(i) * 0.09), lineWidth: 2)
                            .te_uniformScale(1.0 + Double(i) * 0.28 + 0.15 * sin(wavePhase + Double(i) * 1.2))
                            .frame(width: 130, height: 130)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: ptt.isTalking)
                    }
                }

                // Main PTT button
                ZStack {
                    // Outer glow ring
                    Circle()
                        .fill(ptt.isTalking
                              ? channelColor.opacity(0.22)
                              : Color.white.opacity(0.04))
                        .frame(width: 148, height: 148)
                        .animation(.easeInOut(duration: 0.15), value: ptt.isTalking)

                    // Button body
                    Circle()
                        .fill(
                            ptt.isTalking
                                ? LinearGradient(colors: [channelColor, channelColor.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color(hex: "#1a2535"), Color(hex: "#0f1820")], startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 128, height: 128)
                        .overlay(
                            Circle()
                                .stroke(
                                    ptt.isTalking ? channelColor : Color.white.opacity(0.12),
                                    lineWidth: ptt.isTalking ? 2.5 : 1.5
                                )
                        )
                        .shadow(
                            color: ptt.isTalking ? channelColor.opacity(0.6) : .black.opacity(0.5),
                            radius: ptt.isTalking ? 20 : 10, y: 4
                        )
                        .animation(.easeInOut(duration: 0.12), value: ptt.isTalking)

                    // Icon + label
                    VStack(spacing: 6) {
                        Image(systemName: ptt.isTalking ? "mic.fill" : "mic")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(ptt.isTalking ? .white : .white.opacity(0.6))
                        Text(ptt.isTalking ? "TRANSMITTING" : "PUSH TO TALK")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(ptt.isTalking ? .white.opacity(0.9) : .white.opacity(0.3))
                            .kerning(1.2)
                    }
                }
                .te_uniformScale(pttScale)
                // Hold gesture
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !ptt.isTalking {
                                withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) { pttScale = 0.93 }
                                ptt.startTransmitting()
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) { pttScale = 1.0 }
                            ptt.stopTransmitting()
                        }
                )
                .disabled(!ptt.connectionState.isOnAir)
                .opacity(ptt.connectionState.isOnAir ? 1 : 0.4)
            }
            .frame(height: 180)

            // Status text below button
            Group {
                if case .connecting = ptt.connectionState {
                    HStack(spacing: 8) {
                        ProgressView().tint(channelColor).te_uniformScale(0.75)
                        Text("Joining channel…")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }
                } else if ptt.connectionState.isOnAir {
                    Text(ptt.isTalking ? "Release to end transmission" : "Hold button to transmit")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(ptt.isTalking ? 0.9 : 0.35))
                        .animation(.easeInOut(duration: 0.2), value: ptt.isTalking)
                } else {
                    Button(action: { ptt.join(channel: ptt.currentChannel) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Join Channel")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [orange, Color(hex: "#e65000")], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(24)
                        .shadow(color: orange.opacity(0.45), radius: 12, y: 4)
                    }
                }
            }
        }
    }

    // MARK: - Recent Transmissions

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
                    .kerning(1.5)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 4) {
                ForEach(ptt.recentTransmissions.prefix(4)) { tx in
                    TransmissionRow(tx: tx)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Active Speaker Chip

private struct ActiveSpeakerChip: View {
    let speaker: PTTSpeaker
    let channelColor: Color

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(channelColor.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundColor(channelColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(speaker.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if speaker.isTalking {
                    SoundWaveIndicator()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .background(channelColor.opacity(0.08))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(channelColor.opacity(speaker.isTalking ? 0.7 : 0.2), lineWidth: 1)
        )
    }
}

// MARK: - Sound Wave Indicator

private struct SoundWaveIndicator: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: "#22d474"))
                    .frame(width: 2, height: 4 + 5 * abs(sin(phase + Double(i) * 0.8)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Transmission Row

private struct TransmissionRow: View {
    let tx: PTTTransmission

    private var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(tx.timestamp))
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tx.speakerName == "You" ? "mic.fill" : "waveform")
                .font(.system(size: 12))
                .foregroundColor(tx.speakerName == "You" ? Color(hex: "#ff6b00") : Color(hex: "#00d4ff"))
                .frame(width: 20)

            Text(tx.speakerName)
                .font(.system(size: 13, weight: tx.speakerName == "You" ? .bold : .medium))
                .foregroundColor(.white.opacity(0.8))

            Text("\(tx.durationSeconds)s")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

// MARK: - Channel Picker Sheet

private struct ChannelPickerSheet: View {
    let ptt: PushToTalkService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#08111a").ignoresSafeArea()
                List {
                    ForEach(PTTChannel.allCases) { channel in
                        Button(action: {
                            ptt.join(channel: channel)
                            dismiss()
                        }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: channel.colorHex).opacity(0.15))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: channel.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Color(hex: channel.colorHex))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.rawValue)
                                        .font(.system(size: 15, weight: ptt.currentChannel == channel ? .bold : .medium))
                                        .foregroundColor(.white)
                                    Text(channel.agoraChannelId)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                Spacer()
                                if ptt.currentChannel == channel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: channel.colorHex))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color(hex: "#0d1b2a").opacity(0.7))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: "#ff6b00"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
