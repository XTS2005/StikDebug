//  SettingsView.swift
//  StikDebug
//
//  Created by Stephen on 3/27/25.

import SwiftUI
import UIKit

private enum SettingsLinks {
    static let githubStars = URL(string: "https://github.com/StephenDev0/StikDebug/stargazers")!
    static let pairingFileGuide = URL(string: "https://github.com/StephenDev0/StikDebug-Guide/blob/main/pairing_file.md")!
    static let localDevVPN = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let discord = URL(string: "https://discord.gg/qahjXNTDwS")!
}

struct SettingsView: View {
    @AppStorage(UserDefaults.Keys.txmOverride) private var overrideTXMDetection = false
    @AppStorage(UserDefaults.Keys.confirmExternalJITRequests) private var confirmExternalJITRequests = true
    @AppStorage("keepAliveAudio") private var keepAliveAudio = true
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true
    @AppStorage(UserDefaults.Keys.targetDeviceIP) private var targetDeviceIP = DeviceConnectionContext.defaultTargetIPAddress

    @State private var isShowingPairingFilePicker = false
    @State private var isImportingFile = false
    @State private var pairingImportMessage: (text: String, isError: Bool)?
    @State private var showDDIConfirmation = false
    @State private var isRedownloadingDDI = false
    @State private var ddiDownloadProgress: Double = 0.0
    @State private var ddiStatusMessage: String = ""
    @State private var ddiResultMessage: (text: String, isError: Bool)?

    private var appVersion: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image("StikDebug")
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text("StikDebug").font(.title2.weight(.semibold))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }

                Section {
                    Link(destination: SettingsLinks.githubStars) {
                        Label("Star on GitHub", systemImage: "star")
                    }
                }

                Section("配对文件") {
                    Button {
                        isShowingPairingFilePicker = true
                    } label: {
                        Label("导入配对文件", systemImage: "doc.badge.plus")
                    }
                    .disabled(isImportingFile)

                    if isImportingFile {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在导入配对文件…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let pairingImportMessage {
                        Label(
                            pairingImportMessage.text,
                            systemImage: pairingImportMessage.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(pairingImportMessage.isError ? .red : .green)
                    }
                }

                Section {
                    Toggle(isOn: $keepAliveAudio) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("静音音频")
                            Text("播放人耳听不到的音频，使 iOS 保持应用运行。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: keepAliveAudio) { _, enabled in
                        if enabled { BackgroundAudioManager.shared.start() }
                        else { BackgroundAudioManager.shared.stop() }
                    }

                    Toggle(isOn: $keepAliveLocation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("后台定位")
                            Text("在需要时使用低精度定位来保持应用存活。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: keepAliveLocation) { _, enabled in
                        if !enabled { BackgroundLocationManager.shared.stop() }
                    }

                } header: {
                    Text("后台保活")
                }

                Section("行为") {
                    Toggle(isOn: $confirmExternalJITRequests) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("确认 JIT 链接")
                            Text("外部链接启用 JIT 或运行脚本前询问。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $overrideTXMDetection) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("始终运行脚本")
                            Text("将设备视为支持 TXM，以绕过硬件检查。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("高级") {
                    HStack {
                        Text("目标设备 IP")
                        Spacer()
                        TextField(DeviceConnectionContext.defaultTargetIPAddress, text: $targetDeviceIP)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 160)
                    }
                    Button { openAppFolder() } label: {
                        Label("应用文件夹", systemImage: "folder")
                    }.foregroundStyle(.primary)
                    Button { showDDIConfirmation = true } label: {
                        Label("重新下载 DDI", systemImage: "arrow.down.circle")
                    }.foregroundStyle(.primary).disabled(isRedownloadingDDI)
                    if isRedownloadingDDI {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: ddiDownloadProgress, total: 1.0)
                            Text(ddiStatusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let result = ddiResultMessage {
                        Text(result.text).font(.caption).foregroundStyle(result.isError ? .red : .green)
                    }
                }

                Section("帮助") {
                    Link(destination: SettingsLinks.pairingFileGuide) {
                        Label("配对文件指南", systemImage: "questionmark.circle")
                    }
                    Link(destination: SettingsLinks.localDevVPN) {
                        Label("下载 LocalDevVPN", systemImage: "arrow.down.circle")
                    }
                    Link(destination: SettingsLinks.discord) {
                        Label("Discord 支持", systemImage: "bubble.left.and.bubble.right")
                    }
                }

                Section {
                    Text(versionFooter)
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("设置")
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }

                let fileManager = FileManager.default
                isImportingFile = true
                pairingImportMessage = nil

                do {
                    try PairingFileStore.importFromPicker(url, fileManager: fileManager)
                    isImportingFile = false
                    pairingImportMessage = ("导入成功", false)
                    startTunnelInBackground()
                    schedulePairingStatusDismiss()
                } catch {
                    isImportingFile = false
                    pairingImportMessage = ("导入失败：\(error.localizedDescription)", true)
                    schedulePairingStatusDismiss()
                }
            case .failure(let error):
                isImportingFile = false
                pairingImportMessage = ("导入失败：\(error.localizedDescription)", true)
                schedulePairingStatusDismiss()
            }
        }
        .confirmationDialog("重新下载 DDI 文件？", isPresented: $showDDIConfirmation, titleVisibility: .visible) {
            Button("重新下载", role: .destructive) {
                redownloadDDIPressed()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("现有 DDI 文件将在下载新副本前被移除。")
        }
    }

    private var versionFooter: String {
        let processInfo = ProcessInfo.processInfo
        let txmLabel: String
        if processInfo.isTXMOverridden {
            txmLabel = "TXM (覆盖)"
        } else {
            txmLabel = processInfo.hasTXM ? "TXM" : "非 TXM"
        }
        return "版本 \(appVersion) • iOS \(UIDevice.current.systemVersion) • \(txmLabel)"
    }

    // MARK: - Business Logic

    private func openAppFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let path = documentsURL.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        if let url = URL(string: path) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func redownloadDDIPressed() {
        guard !isRedownloadingDDI else { return }
        Task {
            await MainActor.run {
                isRedownloadingDDI = true
                ddiDownloadProgress = 0
                ddiStatusMessage = "正在准备下载…"
                ddiResultMessage = nil
            }
            do {
                try await redownloadDDI { progress, status in
                    Task { @MainActor in
                        self.ddiDownloadProgress = progress
                        self.ddiStatusMessage = status
                    }
                }
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("DDI 文件已成功刷新。", false)
                }
            } catch {
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("重新下载 DDI 文件失败：\(error.localizedDescription)", true)
                }
            }
        }
        scheduleDDIStatusDismiss()
    }

    private func schedulePairingStatusDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !isImportingFile {
                    pairingImportMessage = nil
                }
            }
        }
    }

    private func scheduleDDIStatusDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !isRedownloadingDDI {
                    ddiResultMessage = nil
                }
            }
        }
    }
}
