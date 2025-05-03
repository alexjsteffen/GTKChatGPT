import Adwaita
import ChatGPTSwift

struct ChatListView: WindowView, @unchecked Sendable {

    var window: AdwaitaWindow
    var app: AdwaitaApp!

    @State private var width = 650
    @State private var height = 550
    @State private var maximized = false
    @State("gptModel") private var selectedModel = ChatGPTModel.gpt_hyphen_4o_hyphen_mini.rawValue
    @State("systemPrompt") private var systemPrompt = "You're a helpful assistant"
    enum Backend: String, CaseIterable, Identifiable {
        case openai = "OpenAI"
        case custom = "Custom"
        var id: String { self.rawValue }
    }
    @State("backend") private var selectedBackend: Backend = .openai
    @State("apiBaseURL") private var apiBaseURL = ""
    @State private var models: [String] = ChatGPTModel.allCases.map { $0.rawValue }
    @State("temperature") private var temperature: Double = 0.5

    @State private var chatState = ChatListState()
    @State private var showAbout = false
    @State private var showPreferences = false
    @State("apiKey") private var apiKey =
        ""
    nonisolated(unsafe) static var chatListScrollView: ChatListScrollView?

    static var chatGPTAPI: ChatGPTAPI = ChatGPTAPI(apiKey: "")

    var view: Body {
        VStack {
            ChatListScrollView { _ in
                ForEach(chatState.messages) { message in
                    HStack {
                        Avatar(showInitials: true, size: 20)
                            .text(message.sender)
                            .padding(16, .leading)
                            .padding(16, .vertical)
                            .valign(.start)

                        VStack {
                            Text(message.text)
                                .xalign(0)
                                .wrap()
                                .selectable()
                                .padding(16, .horizontal)
                                .padding(16, .vertical)
                                .hexpand()
                                .valign(.start)

                            if message.state == .loading {
                                Spinner()
                                    .padding(16, .vertical)
                            }

                            if message.state == .error {
                                Button("Retry") {
                                    self.retry(message: message)
                                }
                                .style("suggested-action")
                                .insensitive(chatState.isPrompting)
                                .frame(maxWidth: 100)
                                .padding(16, .horizontal)
                                .padding(16, .vertical)
                                .halign(.start)
                            }
                        }

                    }
                    .padding(8)
                    .style("card")
                }
            }
            .modify { scrollView in
                Self.chatListScrollView = scrollView
            }
            .kineticScrolling()
            .propagateNaturalHeight()
            .vexpand()

            HStack {
                EntryRow("Enter message to send", text: $chatState.text)
                    .entryActivated {
                        let text = self.chatState.text
                        guard !text.isEmpty else { return }
                        self.chatState.text = ""
                        self.sendMessage(text: text)
                    }
                    .hexpand()
                    .padding(8, .trailing)

                if chatState.task != nil {
                    Button("Cancel") {
                        self.chatState.task?.cancel()
                        self.chatState.task = nil
                    }
                    .style("destructive-action")
                } else {
                    HStack {
                        Button(icon: Icon.default(icon: .preferencesSystem)) {
                            showPreferences = true
                        }
                        .padding(8, .trailing)
                        .insensitive(chatState.isPrompting)

                        Button("Clear") {
                            self.chatState.messages.removeAll()
                            self.chatState.messages.append(
                                .init(
                                    sender: "A I", text: "Hello there! how may i assist you?",
                                    role: .assistant, state: .idle))
                        }
                        .style("destructive-action")
                        .padding(8, .trailing)
                        .insensitive(chatState.isPrompting)

                        Button("Send") {

                            let text = self.chatState.text
                            guard !text.isEmpty else { return }
                            self.chatState.text = ""
                            self.sendMessage(text: text)
                        }
                        .style("suggested-action")
                        .insensitive(chatState.isPrompting)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: 768)

        .topToolbar {

            HeaderBar.end {
                Menu(icon: .default(icon: .openMenu)) {
                    MenuSection {
                        MenuButton("Preferences") { showPreferences = true }
                            .keyboardShortcut("comma".ctrl())
                        MenuButton("About") { showAbout = true }

                        MenuButton("Quit", window: false) { app.quit() }
                            .keyboardShortcut("q".ctrl())
                    }
                }
                .primary()
                .tooltip("Main Menu")

            }
            .headerBarTitle {
                WindowTitle(subtitle: "GPT Model - \(selectedModel)", title: "XCA AI Chat")

            }

        }
        .onAppear {
            Self.updateAPI(apiKey: apiKey, apiBaseURL: apiBaseURL)
        }
        .aboutDialog(
            visible: $showAbout,
            app: "XCA AI Chat",
            developer: "Alfian Losari - Xcoding with Alfian",
            version: "0.1.2",
            icon: .custom(name: "io.github.alfianlosari.GTKChatGPT"),
            website: .init(string: "https://github.com/alfianlosari/GTKChatGPT"),
            issues: .init(string: "https://github.com/alfianlosari/GTKChatGPT/issues")
        )
        .alertDialog(
            visible: $showPreferences, heading: "Settings", body: "Bring your own OpenAI API Key and custom endpoint (optional)"
        ) {
            ScrollView {
                VStack {
                    FormSection("API") {
                        Form {
                            ComboRow("Backend", selection: $selectedBackend, values: Backend.allCases.map { $0.rawValue })
                            EntryRow("API Key", text: $apiKey)
                                .secure(text: $apiKey)
                            if selectedBackend == .custom {
                                EntryRow("Custom API Endpoint", text: $apiBaseURL)
                                    .placeholder("https://your.custom.endpoint/v1")
                            }
                            if selectedBackend == .openai {
                                LinkButton(uri: "https://platform.openai.com")
                            }
                        }
                    }
                    .padding()

                    FormSection("Configuration") {
                        Form {
                            ComboRow("ChatGPT Model", selection: $selectedModel, values: models)
                            Button("Update Models") {
                                Self.updateModels()
                            }
                            .style("suggested-action")
                            EntryRow("System Prompt", text: $systemPrompt)
                            SpinRow(
                                "Temperature", value: $temperature,
                                min: 0.0, max: 1.0
                            )
                            .step(0.1)
                            .digits(1)
                            .subtitle("Response Creativity")
                        }
                    }
                    .padding()
    // Helper to update models from API
    static func fetchModels(apiKey: String, backend: Backend, apiBaseURL: String, completion: @escaping ([String]) -> Void) {
        let baseURL: String
        switch backend {
        case .openai:
            baseURL = "https://api.openai.com/v1"
        case .custom:
            baseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !baseURL.isEmpty, let url = URL(string: baseURL + "/models") else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion([])
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let modelList = json["data"] as? [[String: Any]] {
                    let ids = modelList.compactMap { $0["id"] as? String }
                    completion(ids)
                } else {
                    completion([])
                }
            } catch {
                completion([])
            }
        }
        task.resume()
    }

    func updateModels() {
        Self.fetchModels(apiKey: apiKey, backend: selectedBackend, apiBaseURL: apiBaseURL) { ids in
            DispatchQueue.main.async {
                if !ids.isEmpty {
                    self.models = ids
                    if !ids.contains(self.selectedModel) {
                        self.selectedModel = ids.first ?? ""
                    }
                }
            }
        }
    }
                }
            }
            .frame(minWidth: 512, minHeight: 210)
            .frame(maxWidth: 768)
            .frame(maxHeight: 512)
        }
        .response("Close", appearance: .suggested, role: .close) {
            Self.updateAPI(apiKey: apiKey, apiBaseURL: apiBaseURL)
        }
    // Helper to update ChatGPTAPI instance with custom endpoint
    static func updateAPI(apiKey: String, apiBaseURL: String, backend: Backend = .openai) {
        let baseURL: String
        switch backend {
        case .openai:
            baseURL = "https://api.openai.com/v1"
        case .custom:
            baseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if baseURL.isEmpty {
            chatGPTAPI = ChatGPTAPI(apiKey: apiKey)
        } else {
            chatGPTAPI = ChatGPTAPI(apiKey: apiKey, apiBaseURL: baseURL)
        }
    }
    }

    func sendMessage(text: String) {
        self.chatState.messages.append(
            .init(sender: "M E", text: text, role: .user, state: .idle))
        self.chatState.messages.append(
            .init(sender: "A I", text: "", role: .assistant, state: .loading))
        self.chatState.isPrompting = true
        self.scrollToBottom()

        self.chatState.task = Task {
            do {
                let stream = try await Self.chatGPTAPI.sendMessageStream(
                    text: text,
                    model: ChatGPTModel(rawValue: selectedModel) ?? .gpt_hyphen_4o,
                    systemText: systemPrompt,
                    temperature: temperature
                )

                var responseText = ""
                for try await text in stream {
                    try Task.checkCancellation()
                    Idle {
                        responseText += text
                        if var message = self.chatState.messages.last {
                            message.text = responseText
                            self.chatState.messages[self.chatState.messages.count - 1] = message
                            self.scrollToBottom()
                        }
                    }
                }
                try Task.checkCancellation()
                Idle {
                    if var message = self.chatState.messages.last {
                        message.text = responseText
                        message.state = .idle
                        self.chatState.messages[self.chatState.messages.count - 1] = message
                        self.chatState.task = nil
                        self.chatState.isPrompting = false
                        self.scrollToBottom()
                        Self.chatGPTAPI.appendToHistoryList(
                            userText: text, responseText: responseText)
                    }
                }
            } catch {
                if var message = self.chatState.messages.last {
                    Idle {
                        if !message.text.isEmpty {
                            message.text += "\n\n"
                        }

                        if error is CancellationError {
                            message.text += "Cancelled"
                        } else {
                            message.text += "Error:\n\(error.localizedDescription)"
                            message.text +=
                                "\n\nSomething went wrong. Please check your API key, billing, model access, or try again later."
                        }
                        message.state = .error
                        self.chatState.messages[self.chatState.messages.count - 1] = message
                        self.chatState.task = nil
                        self.chatState.isPrompting = false
                        self.scrollToBottom()
                    }
                }
            }
        }
    }

    func retry(message: Message) {
        guard let index = self.chatState.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        let promptMessage = self.chatState.messages[index - 1]
        self.chatState.messages.remove(at: index)
        self.chatState.messages.remove(at: index - 1)
        Idle(delay: Duration.seconds(0.1)) {
            self.sendMessage(text: promptMessage.text)
            return false
        }
    }

    func scrollToBottom() {
        Self.chatListScrollView?.scrollToBottom()
    }

    func window(_ window: Core.Window) -> Core.Window {
        window
            .size(width: $width, height: $height)
            .maximized($maximized)
            .resizable(true)
            .closeShortcut()
            .title("XCA AI Chat")
    }

}
