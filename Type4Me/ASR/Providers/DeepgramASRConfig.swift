import Foundation

struct DeepgramASRConfig: ASRProviderConfig, Sendable {

    static let provider = ASRProvider.deepgram
    static let displayName = "Deepgram"
    static let defaultModel = "nova-2"
    static let defaultLanguage = "zh"

    static var credentialFields: [CredentialField] {[
        CredentialField(key: "apiKey", label: "API Key", placeholder: "dg_...", isSecure: true, isOptional: false, defaultValue: ""),
        CredentialField(key: "model", label: "Model", placeholder: defaultModel, isSecure: false, isOptional: false, defaultValue: defaultModel),
        CredentialField(key: "language", label: "Language", placeholder: defaultLanguage, isSecure: false, isOptional: false, defaultValue: defaultLanguage),
    ]}

    let apiKey: String
    let model: String
    let language: String

    init?(credentials: [String: String]) {
        guard let apiKey = credentials["apiKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else { return nil }

        let model = credentials["model"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = credentials["language"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.apiKey = apiKey
        self.model = model?.isEmpty == false ? model! : Self.defaultModel
        self.language = language?.isEmpty == false ? language! : Self.defaultLanguage
    }

    func toCredentials() -> [String: String] {
        [
            "apiKey": apiKey,
            "model": model,
            "language": language,
        ]
    }

    var isValid: Bool {
        !apiKey.isEmpty && !model.isEmpty && !language.isEmpty
    }
}
