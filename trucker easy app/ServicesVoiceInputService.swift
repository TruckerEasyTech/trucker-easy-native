import Foundation
import AVFoundation
import Speech
import Observation
import SwiftUI

/// A speech-to-text service for iOS using AVAudioEngine and SFSpeechRecognizer.
///
/// Use this service in a SwiftUI View by observing its published properties.
/// For example:
/// ```swift
/// @StateObject private var voiceInputService = VoiceInputService()
///
/// var body: some View {
///   VStack {
///     Text(voiceInputService.transcript)
///     if voiceInputService.isListening {
///       Text("Listening...").foregroundColor(.green)
///     }
///     Button(voiceInputService.isListening ? "Stop" : "Start") {
///       if voiceInputService.isListening {
///         voiceInputService.stopListening()
///       } else {
///         Task {
///           await voiceInputService.startListening()
///         }
///       }
///     }
///     if let error = voiceInputService.errorMessage {
///       Text(error).foregroundColor(.red)
///     }
///   }
/// }
/// ```
@Observable
public final class VoiceInputService {
  
  // MARK: - Public Read-only Properties
  
  /// Indicates whether the service is currently listening for speech input.
  public private(set) var isListening: Bool = false
  
  /// The current transcribed text from the speech recognition.
  public private(set) var transcript: String = ""
  
  /// An optional error message describing the last failure, if any.
  public private(set) var errorMessage: String? = nil
  
  // MARK: - Private Properties
  
  private let audioEngine = AVAudioEngine()
  private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current)
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var isAudioTapInstalled = false
  
  // MARK: - Public Methods
  
  /// Requests microphone and speech recognition permissions.
  ///
  /// - Parameter completion: Called on main thread with `true` if all permissions granted, otherwise `false`.
  public func requestPermissions(completion: @escaping (Bool) -> Void) {
    // Request microphone permission first
    let handleSpeech: (Bool) -> Void = { micGranted in
      SFSpeechRecognizer.requestAuthorization { speechAuthStatus in
        let speechGranted = (speechAuthStatus == .authorized)
        DispatchQueue.main.async {
          completion(micGranted && speechGranted)
        }
      }
    }
    if #available(iOS 17, *) {
      AVAudioApplication.requestRecordPermission { micGranted in
        handleSpeech(micGranted)
      }
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
        handleSpeech(micGranted)
      }
    }
  }
  
  /// Starts listening for speech input and updates the transcript live.
  ///
  /// This method is safe to call from async contexts.
  /// If the service is already listening, this method returns immediately.
  ///
  /// On error, `errorMessage` is set, and `isListening` is reset to false.
  public func startListening() async {
    await MainActor.run {
      self.errorMessage = nil
      if self.isListening {
        return
      }
    }
    
    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
      await updateError("Speech recognizer is not available.")
      return
    }
    
    do {
      try configureAudioSession()
    } catch {
      await updateError("Failed to configure audio session: \(error.localizedDescription)")
      return
    }
    
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    
    recognitionRequest = request
    
    let inputNode = audioEngine.inputNode

    if isAudioTapInstalled {
      inputNode.removeTap(onBus: 0)
      isAudioTapInstalled = false
    }
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
      guard let self, self.isListening else { return }
      guard buffer.frameLength > 0 else { return }
      let byteSize = buffer.audioBufferList.pointee.mBuffers.mDataByteSize
      guard byteSize > 0 else {
        // #region agent log
        print("[DBG][VOICE][H-audio-2] skip empty AVAudioBuffer byteSize=0")
        // #endregion
        return
      }
      request.append(buffer)
    }
    isAudioTapInstalled = true
    // #region agent log
    print("[DBG][VOICE][H-v1] installTap success")
    // #endregion
    
    do {
      try audioEngine.start()
    } catch {
      await updateError("Audio engine failed to start: \(error.localizedDescription)")
      cleanupAudio()
      return
    }
    
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self = self else { return }
      
      if let result = result {
        Task { @MainActor in
          self.transcript = result.bestTranscription.formattedString
        }
      }
      
      if let error = error {
        Task { @MainActor in
          self.errorMessage = "Recognition error: \(error.localizedDescription)"
          self.stopListening()
        }
      }
      
      if let result = result, result.isFinal {
        Task { @MainActor in
          self.isListening = false
          self.stopListening()
        }
      }
    }
    
    await MainActor.run {
      self.isListening = true
      self.transcript = ""
      self.errorMessage = nil
    }
  }
  
  /// Stops listening for speech input.
  ///
  /// After calling this method, `isListening` will be false.
  public func stopListening() {
    audioEngine.stop()
    if isAudioTapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      isAudioTapInstalled = false
      // #region agent log
      print("[DBG][VOICE][H-v1] removeTap success on stop")
      // #endregion
    }
    
    recognitionTask?.cancel()
    recognitionTask = nil
    
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    
    Task { @MainActor in
      self.isListening = false
    }
  }
  
  // MARK: - Private Helpers
  
  private func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
    try session.setMode(.default)
    try session.setActive(true, options: .notifyOthersOnDeactivation)
  }
  
  @MainActor
  private func updateError(_ message: String) async {
    self.errorMessage = message
    self.isListening = false
  }
  
  private func cleanupAudio() {
    audioEngine.stop()
    if isAudioTapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      isAudioTapInstalled = false
      // #region agent log
      print("[DBG][VOICE][H-v1] removeTap success on cleanup")
      // #endregion
    }
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    Task { @MainActor in
      self.isListening = false
    }
  }
}

