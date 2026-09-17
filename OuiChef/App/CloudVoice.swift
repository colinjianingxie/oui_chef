import AVFoundation
import Foundation

/// Provider-independent PCM transport. Provider event translation lives on the server.
@MainActor
final class CloudVoice {
    var onEvent: (([String: Any]) -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let account = CloudVoiceAccount()
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var readyTimeout: Task<Void, Never>?
    private var tapInstalled = false
    private var generation = UUID()
    private var audioGeneration = UUID()
    private var queuedBuffers = 0
    private var currentItem: String?
    private var currentResponse: String?
    private var interruptedResponses = Set<String>()
    private var playbackStart: AVAudioFramePosition = 0
    private var receivedFrames: AVAudioFramePosition = 0
    private var playbackRate: Double = 24000
    private var waitingForReady = true
    private var captureStarted = false
    private var configurationObserver: NSObjectProtocol?
    private var outputQueue: AsyncStream<URLSessionWebSocketTask.Message>.Continuation?
    var uid: String? { account.uid }

    init() {
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.socket != nil, self.tapInstalled, !self.engine.isRunning else { return }
                guard !self.captureStarted else { self.fail("Audio changed. Tap to reconnect voice; your timers keep running."); return }
                // iOS may stop the engine while the initial voice-chat route settles.
                // Rebuild the tap/converter from the new input format within the startup timeout.
                self.player.stop()
                self.engine.inputNode.removeTap(onBus: 0)
                self.tapInstalled = false
                do { try self.startAudio() }
                catch { self.fail("The microphone couldn't restart: \(error.localizedDescription)") }
            }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    func start(context: [String: Any]) async throws {
        guard let endpoint = CloudVoiceAccount.endpoint else { throw CookingError.invalid("Cloud voice is not configured.") }
        let current = UUID()
        generation = current
        let token = try await account.idToken()
        guard generation == current, !Task.isCancelled else { return }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 1000000
        self.socket = socket
        waitingForReady = true
        captureStarted = false
        let stream = AsyncStream<URLSessionWebSocketTask.Message>(bufferingPolicy: .bufferingOldest(80)) { outputQueue = $0 }
        socket.resume()
        readyTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.generation == current, !self.captureStarted else { return }
            self.fail(self.waitingForReady ? "Your chef couldn't connect. Check your connection and try again." : "The microphone isn't sending audio. Try reconnecting voice.")
        }
        sendTask = Task { [weak self] in
            do {
                for await message in stream {
                    try Task.checkCancellation()
                    try await socket.send(message)
                    guard let self, self.generation == current else { return }
                    if !self.captureStarted, case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       event["type"] as? String == "audio" {
                        self.captureStarted = true
                        self.readyTimeout?.cancel()
                        self.onEvent?(["type": "ready"])
                    }
                }
            }
            catch { if self?.generation == current { self?.connectionFailed(socket) } }
        }
        send(["type": "start", "context": context])
        receiveTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == current else { return }
                    let data: Data
                    switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: continue }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    try self.receive(event)
                }
            } catch {
                if self?.generation == current { self?.connectionFailed(socket) }
            }
        }
    }
    func send(_ event: [String: Any]) {
        guard let outputQueue else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: event)
            guard let text = String(data: data, encoding: .utf8) else { return }
            if case .dropped = outputQueue.yield(.string(text)) { fail("Voice connection is too slow. Tap to reconnect.") }
        } catch { fail("Could not send cooking context to voice.") }
    }
    private func receive(_ event: [String: Any]) throws {
        switch event["type"] as? String {
        case "ready":
            guard waitingForReady else { return }
            do { try startAudio() }
            catch { fail("The microphone couldn't start: \(error.localizedDescription)"); return }
            waitingForReady = false
            return // Report ready only after the first microphone packet has been sent.
        case "audio":
            if let response = event["responseID"] as? String, interruptedResponses.contains(response) { return }
            currentResponse = event["responseID"] as? String
            guard let raw = event["audio"] as? String, let data = Data(base64Encoded: raw), data.count % 2 == 0 else { return }
            try play(data, item: event["itemID"] as? String)
        case "responding": currentResponse = event["responseID"] as? String
        case "speech_started": interrupt(cancelResponse: false)
        case "ended", "error":
            onEvent?(event)
            stop()
            return
        default: break
        }
        onEvent?(event)
    }
    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        try engine.inputNode.setVoiceProcessingEnabled(true)
        if player.engine == nil { engine.attach(player) }
        guard let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true),
              let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false) else { throw CookingError.invalid("Audio format unavailable.") }
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: wireFormat) else { throw CookingError.invalid("No microphone audio is available.") }
        let current = generation
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] inputBuffer, _ in
            let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * 24000 / format.sampleRate + 32)
            guard let output = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return inputBuffer
            }
            if let error {
                let message = error.localizedDescription
                Task { @MainActor in
                    guard self?.generation == current else { return }
                    self?.fail("Microphone audio couldn't be converted: \(message)")
                }
                return
            }
            guard output.frameLength > 0, let bytes = output.int16ChannelData?[0] else { return }
            let data = Data(bytes: bytes, count: Int(output.frameLength) * 2)
            Task { @MainActor in
                guard self?.generation == current else { return }
                self?.send(["type": "audio", "audio": data.base64EncodedString()])
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        player.play()
    }
    private func play(_ data: Data, item: String?) throws {
        guard data.count <= 1000000, queuedBuffers < 100,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)),
              let samples = buffer.floatChannelData?[0] else { throw CookingError.invalid("Voice playback buffer is full.") }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { bytes in
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32768
            }
        }
        let rendered = player.lastRenderTime.flatMap { player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
        let scheduledStart = max(receivedFrames, rendered)
        if item != currentItem {
            currentItem = item
            playbackStart = scheduledStart
        }
        receivedFrames = scheduledStart + AVAudioFramePosition(buffer.frameLength)
        queuedBuffers += 1
        let current = audioGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.audioGeneration == current else { return }
                self.queuedBuffers = max(0, self.queuedBuffers - 1)
                if self.queuedBuffers == 0 { self.onEvent?(["type": "playback_finished"]) }
            }
        }
        if !player.isPlaying { player.play() }
    }
    func interrupt(cancelResponse: Bool = true) {
        if let response = currentResponse { interruptedResponses.insert(response) }
        var event: [String: Any] = ["type": "interrupt", "cancelResponse": cancelResponse]
        if let item = currentItem, let time = player.lastRenderTime, let played = player.playerTime(forNodeTime: time) {
            event["itemID"] = item
            let heardFrames = max(0, min(played.sampleTime - playbackStart, receivedFrames - playbackStart))
            event["playedMs"] = Double(heardFrames) / playbackRate * 1000
        }
        send(event)
        audioGeneration = UUID()
        player.stop()
        queuedBuffers = 0; currentItem = nil; receivedFrames = 0; playbackStart = 0
        if engine.isRunning { player.play() }
        onEvent?(["type": "playback_finished"])
    }
    func stop() {
        generation = UUID(); audioGeneration = UUID()
        captureStarted = false
        outputQueue?.finish(); outputQueue = nil
        readyTimeout?.cancel(); readyTimeout = nil
        receiveTask?.cancel(); sendTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        player.stop(); engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        queuedBuffers = 0; receivedFrames = 0; currentItem = nil
        currentResponse = nil; interruptedResponses = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func connectionFailed(_ socket: URLSessionWebSocketTask) {
        if (socket.response as? HTTPURLResponse)?.statusCode == 403 {
            fail("Voice access hasn't been enabled for this iPhone. Share the development tester ID below to enable it.", code: "access_denied")
        } else {
            fail("Voice disconnected. Check your connection and try again. Your timers keep running.")
        }
    }
    private func fail(_ message: String, code: String = "connection") {
        onEvent?(["type": "ended", "message": message, "code": code]); stop()
    }
}
