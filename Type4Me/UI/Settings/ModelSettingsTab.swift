import SwiftUI

struct ModelSettingsTab: View, SettingsCardHelpers {

    @AppStorage("tf_use_cloud") private var useCloud = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(
                label: "MODELS",
                title: L("模型配置", "Model Configuration"),
                description: L("语音识别与文本处理引擎配置。", "ASR and LLM engine configuration.")
            )

            // Cloud / BYOK toggle
            settingsSegmentedPicker(
                selection: Binding(
                    get: { useCloud ? "cloud" : "byok" },
                    set: { useCloud = $0 == "cloud" }
                ),
                options: [
                    ("cloud", "Type4Me Cloud"),
                    ("byok", L("自定义 API", "Custom API")),
                ]
            )
            .padding(.bottom, 16)

            if useCloud {
                CloudSettingsCard()
            } else {
                ASRSettingsCard()

                Spacer().frame(height: 16)

                LLMSettingsCard()
            }
        }
        .onChange(of: useCloud) { _, newValue in
            if newValue {
                KeychainService.selectedASRProvider = .cloud
            }
        }
    }
}
