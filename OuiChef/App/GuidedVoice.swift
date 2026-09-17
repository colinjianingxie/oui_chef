import AVFoundation
import Speech
import Observation
import UIKit

@MainActor @Observable
final class GuidedVoice: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var enabled = false
    private(set) var isListening = false
    private(set) var isStarting = false
    private(set) var needsSettings = false
    private(set) var needsTesterAccess = false
    private(set) var isSpeaking = false
    private(set) var hearingSpeech = false
    private(set) var transcript = ""
    private(set) var status = "Microphone off"
    private(set) var lastInteraction = Date.distantPast
    var onCommand: ((String) -> Void)?
    var onReady: (() -> Void)?
    var context: (() -> [String: Any])?
    var onTool: ((String, String, String) async -> String)?
    var onAssistantText: ((String) -> Void)?
    private(set) var userTurn = 0
    private(set) var usingCloud = false
    private(set) var isResponding = false
    private(set) var testerID: String?
    private let cloud = CloudVoice()
    var cloudSelected: Bool { UserDefaults.standard.object(forKey: "useCloudVoice") as? Bool ?? (CloudVoiceAccount.endpoint != nil) }

    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var debounce: Task<Void, Never>?
    private var toolTask: Task<Void, Never>?
    var connectionID: UUID { generation }
    private var generation = UUID()
    private var tapInstalled = false
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        testerID = cloud.uid
        synthesizer.delegate = self
        cloud.onEvent = { [weak self] event in self?.cloudEvent(event) }
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.stop(); self?.status = "Audio interrupted. Tap to resume voice." }
        }
    }

    func refreshTesterID() { testerID = cloud.uid }

    func start() async {
        guard !enabled, !isStarting else { return }
        isStarting = true
        let attempt = UUID()
        generation = attempt
        defer { if generation == attempt { isStarting = false } }
        needsSettings = false; needsTesterAccess = false; transcript = ""
        status = "Getting your microphone ready…"
        if cloudSelected {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard generation == attempt else { return }
            guard granted else { needsSettings = true; status = "Allow microphone access in Settings to use voice."; return }
            guard UIApplication.shared.applicationState != .background else { status = "Return to the app to start voice."; return }
            usingCloud = true
            enabled = true
            status = "Connecting to your chef…"
            do {
                try await cloud.start(context: context?() ?? [:])
            } catch {
                stop()
                status = error.localizedDescription
            }
            testerID = cloud.uid
            return
        }
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let micPermission = await AVAudioApplication.requestRecordPermission()
        guard generation == attempt else { return }
        guard speechPermission == .authorized, micPermission else {
            needsSettings = true
            status = "Allow microphone and speech recognition in Settings to use voice."
            return
        }
        guard UIApplication.shared.applicationState != .background else { status = "Return to the app to start voice."; return }
        guard recognizer?.isAvailable == true else { status = "Speech recognition is unavailable. You can keep cooking with the buttons."; return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audio.setActive(true)
            try engine.inputNode.setVoiceProcessingEnabled(true)
            enabled = true
            try listen()
            isStarting = false
            onReady?()
        } catch {
            stop()
            status = "Voice could not start: \(error.localizedDescription)"
        }
    }

    private func listen() throws {
        guard enabled else { return }
        generation = UUID()
        let current = generation
        recognition?.cancel()
        request?.endAudio()
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition == true
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CookingError.invalid("No microphone input is available.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        isListening = true
        status = isSpeaking ? "Speaking · say stop to interrupt" : "Listening"
        recognition = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.enabled, self.generation == current else { return }
                if let words, !words.isEmpty {
                    self.transcript = words
                    self.hearingSpeech = true
                    self.lastInteraction = Date()
                    self.debounce?.cancel()
                    let heardDuringSpeech = self.isSpeaking
                    self.debounce = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(isFinal ? 50 : 850))
                        guard !Task.isCancelled, let self, self.enabled, self.generation == current else { return }
                        self.hearingSpeech = false
                        let command = VoiceCommand.parse(words)
                        // During native speech playback only explicit interruption commands are accepted.
                        // Voice processing reduces echo; full conversational barge-in needs device validation.
                        if !heardDuringSpeech || command == .pause || command == .mute {
                            self.lastInteraction = Date()
                            if self.isSpeaking { self.cancelSpeech() }
                            self.onCommand?(words)
                        }
                        guard self.enabled else { return }
                        do { try self.listen() } catch { self.stop(); self.status = error.localizedDescription }
                    }
                } else if failed {
                    self.stop()
                    self.status = "Listening was interrupted. Tap to reconnect; cooking progress is saved."
                }
            }
        }
    }

    func speak(_ text: String) {
        guard isListening else { return }
        if usingCloud { cloud.send(["type": "cue", "text": text]); return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        isSpeaking = true
        status = "Speaking · say stop to interrupt"
        synthesizer.speak(utterance)
    }
    func cancelSpeech() {
        if usingCloud { cloud.interrupt(); isSpeaking = false; return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        if enabled { status = "Listening" }
    }
    func stop() {
        toolTask?.cancel(); toolTask = nil
        cloud.stop()
        enabled = false
        isListening = false
        isStarting = false
        needsSettings = false
        needsTesterAccess = false
        usingCloud = false
        isResponding = false
        generation = UUID()
        debounce?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        hearingSpeech = false
        recognition?.cancel()
        recognition = nil
        request?.endAudio()
        request = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = "Microphone off"
    }
    func updateContext() {
        if usingCloud && isListening { cloud.send(["type": "context", "context": context?() ?? [:]]) }
    }
    func sendText(_ text: String) {
        guard usingCloud else { onCommand?(text); return }
        guard isListening else { return }
        userTurn += 1
        lastInteraction = Date()
        cloud.send(["type": "text", "text": text])
    }
    private func cloudEvent(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "ready": isListening = true; status = "Listening · xAI"; onReady?()
        case "speech_started": hearingSpeech = true; lastInteraction = Date()
        case "speech_stopped": hearingSpeech = false; userTurn += 1; lastInteraction = Date()
        case "responding": isResponding = true
        case "response_done": isResponding = false
        case "audio": isSpeaking = true; status = "Speaking · you can interrupt"
        case "playback_finished": isSpeaking = false; lastInteraction = Date(); if enabled { status = "Listening · xAI" }
        case "transcript":
            guard let text = event["text"] as? String else { return }
            if event["role"] as? String == "assistant" { onAssistantText?(text) }
            else {
                transcript = text
                let command = VoiceCommand.parse(text)
                if command == .pause || command == .mute { onCommand?(text) }
            }
        case "tool":
            guard let callID = event["callID"] as? String, let name = event["name"] as? String,
                  let arguments = event["arguments"] as? String else { return }
            let previous = toolTask, connection = generation
            toolTask = Task { [weak self] in
                await previous?.value
                guard let self, self.generation == connection, !Task.isCancelled else { return }
                let output = await self.onTool?(callID, name, arguments) ?? "{}"
                guard self.generation == connection, !Task.isCancelled else { return }
                self.cloud.send(["type": "tool_result", "callID": callID, "output": output, "context": self.context?() ?? [:]])
            }
        case "ended", "error":
            let message = event["message"] as? String ?? "Voice ended. Your timers continue."
            stop(); status = message
            testerID = cloud.uid
            needsTesterAccess = event["code"] as? String == "access_denied"
        default: break
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, !self.synthesizer.isSpeaking else { return }
            self.isSpeaking = false
            self.lastInteraction = Date()
            self.hearingSpeech = false
            if self.enabled {
                // Drop the recognition buffer that may contain the assistant's own audio.
                do { try self.listen() } catch { self.stop(); self.status = error.localizedDescription }
            }
        }
    }
}
