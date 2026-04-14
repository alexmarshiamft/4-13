// QuickCaptureViewModel.swift – ViewModel for the global Quick Capture panel
// Lumina: AI-powered reminders, task management, and focus app

import Foundation
import SwiftUI
import SwiftData
#if canImport(Speech)
import Speech
#endif

// MARK: - QuickCaptureViewModel
@MainActor
final class QuickCaptureViewModel: ObservableObject {

    // MARK: - Published Input
    @Published var inputText: String = ""
    @Published var isListening: Bool = false
    @Published var transcribedText: String = ""

    // MARK: - Published Parsed Result (live preview)
    @Published var parsedResult: ParsedTaskResult? = nil
    @Published var showParsedPreview: Bool = false

    // MARK: - Published State
    @Published var isSaving: Bool = false
    @Published var saveError: String? = nil
    @Published var didSave: Bool = false

    // MARK: - Voice
#if canImport(Speech)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: .current)
#endif

    // MARK: - Debounce
    private var parseWorkItem: DispatchWorkItem?

    // MARK: - NLP
    private let parser = NLPParser.shared

    // MARK: - Parse on input change (debounced)
    func onInputChanged(_ text: String) {
        parseWorkItem?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            parsedResult = nil
            showParsedPreview = false
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let result = self.parser.parse(text)
                self.parsedResult = result
                self.showParsedPreview = !result.title.isEmpty
            }
        }
        parseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    // MARK: - Save Task
    func saveTask(context: ModelContext, notificationScheduler: NotificationScheduler) async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let result = parser.parse(text)

        let task = LuminaTask(
            title: result.title.isEmpty ? text : result.title,
            rawInput: text,
            dueDate: result.dueDate,
            dueTime: result.dueTime,
            priority: result.priority,
            tags: result.tags,
            isRecurring: result.isRecurring
        )
        task.associatedCalendarTitle = result.associatedCalendarTitle
        task.recurrenceRuleData = result.recurrenceRule.flatMap { try? JSONEncoder().encode($0) }

        context.insert(task)

        do {
            try context.save()
            await notificationScheduler.schedule(task: task)
            NotificationCenter.default.post(name: .luminaTaskCreated, object: task)
            didSave = true
            reset()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Reset
    func reset() {
        inputText = ""
        parsedResult = nil
        showParsedPreview = false
        saveError = nil
        transcribedText = ""
        stopListening()
    }

    // MARK: - Voice Dictation
    func toggleVoiceDictation() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
#if canImport(Speech)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self else { return }
            Task { @MainActor in
                self.beginRecognition()
            }
        }
#endif
    }

    func stopListening() {
#if canImport(Speech)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
#endif
    }

#if canImport(Speech)
    private func beginRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // privacy: on-device only

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("[Lumina] Audio engine start failed: \(error)")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    let transcript = result.bestTranscription.formattedString
                    self.transcribedText = transcript
                    self.inputText = transcript
                    self.onInputChanged(transcript)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }
    }
#endif
}
