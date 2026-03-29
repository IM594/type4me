import SwiftUI

struct ModelSettingsTab: View, SettingsCardHelpers {

    @State private var coordinator = LocalServerCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(
                label: "MODELS",
                title: L("模型配置", "Model Configuration"),
                description: L("语音识别与文本处理引擎配置。", "ASR and LLM engine configuration.")
            )

            // Local server status card (only when any local provider is active)
            if needsLocalServer {
                localServerStatusCard
                Spacer().frame(height: 16)
            }

            ASRSettingsCard()

            Spacer().frame(height: 16)

            LLMSettingsCard()
        }
        .task {
            await coordinator.refreshStatus()
        }
    }

    private var needsLocalServer: Bool {
        KeychainService.selectedASRProvider == .sherpa
            || KeychainService.selectedLLMProvider == .localQwen
    }

    private var localServerStatusCard: some View {
        settingsGroupCard(L("本地推理服务", "Local Inference Server"), icon: "server.rack") {
            HStack(spacing: 8) {
                Circle()
                    .fill(coordinator.isRunning ? TF.settingsAccentGreen : TF.settingsAccentRed)
                    .frame(width: 8, height: 8)
                Text(coordinator.isRunning
                    ? L("推理服务运行中", "Server running")
                    : L("推理服务未启动", "Server stopped"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TF.settingsText)

                if let port = SenseVoiceServerManager.currentPort, coordinator.isRunning {
                    Text("port:\(port)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(TF.settingsTextTertiary)
                }

                Spacer()

                if coordinator.isStarting {
                    ProgressView()
                        .controlSize(.small)
                } else if coordinator.isRunning {
                    Button(L("停止", "Stop")) {
                        Task {
                            await SenseVoiceServerManager.shared.stop()
                            coordinator.isRunning = false
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(TF.settingsAccentRed)
                    .controlSize(.small)
                } else {
                    Button(L("启动", "Start")) {
                        Task { await coordinator.ensureRunning() }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(TF.settingsAccentAmber)
                    .controlSize(.small)
                }
            }

            // Show which local models are active
            let localASR = KeychainService.selectedASRProvider == .sherpa
            let localLLM = KeychainService.selectedLLMProvider == .localQwen
            if localASR || localLLM {
                HStack(spacing: 16) {
                    if localASR {
                        Label(L("ASR: 本地", "ASR: Local"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TF.settingsAccentGreen)
                    }
                    if localLLM {
                        let modelName = LocalQwenLLMConfig.availableModel?.displayName ?? "Qwen"
                        Label(L("LLM: \(modelName)", "LLM: \(modelName)"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TF.settingsAccentGreen)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
