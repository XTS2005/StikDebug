//
//  TunnelManager.swift
//  StikDebug
//

import Foundation

final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var isConnected = false

    private var isStarting = false

    private init() {}

    func markDisconnected() {
        runOnMain {
            self.isConnected = false
        }
    }

    func start(showErrorUI: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.start(showErrorUI: showErrorUI)
            }
            return
        }

        let pairingFileURL = PairingFileStore.prepareURL()
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            isConnected = false
            return
        }

        guard !isStarting else {
            return
        }

        isStarting = true

        DispatchQueue.global(qos: .userInteractive).async { [showErrorUI] in
            let result: Result<Void, NSError>
            do {
                try JITEnableContext.shared.startTunnel()
                result = .success(())
            } catch {
                result = .failure(error as NSError)
            }

            DispatchQueue.main.async {
                self.finishStart(result, showErrorUI: showErrorUI)
            }
        }
    }

    private func finishStart(_ result: Result<Void, NSError>, showErrorUI: Bool) {
        isStarting = false

        switch result {
        case .success:
            isConnected = true
            LogManager.shared.addInfoLog("Tunnel connected successfully")
            mountDeveloperDiskImageIfNeeded()
        case .failure(let error):
            isConnected = false
            handleStartFailure(error, showErrorUI: showErrorUI)
        }
    }

    private func mountDeveloperDiskImageIfNeeded() {
        let trustcachePath = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path
        guard FileManager.default.fileExists(atPath: trustcachePath),
              !MountingProgress.shared.coolisMounted,
              MountingProgress.shared.mountingThread == nil else {
            return
        }
        MountingProgress.shared.pubMount()
    }

    private func handleStartFailure(_ error: NSError, showErrorUI: Bool) {
        LogManager.shared.addErrorLog(tunnelConnectionLogMessage(for: error))
        guard showErrorUI else {
            return
        }

        if error.code == -9 {
            handleInvalidPairingFile()
            return
        }

        showAlert(
            title: "连接错误",
            message: tunnelConnectionAlertMessage(for: error),
            showOk: false,
            showTryAgain: true
        ) { shouldTryAgain in
            if shouldTryAgain {
                startTunnelInBackground()
            }
        }
    }

    private func handleInvalidPairingFile() {
        LogManager.shared.addInfoLog("Pairing file reported invalid; keeping existing file")

        showAlert(
            title: "无效的配对文件",
            message: "配对文件可能无效或已过期。您可以导入新的配对文件来替换它。",
            showOk: true,
            showTryAgain: false,
            primaryButtonText: "选择新文件"
        ) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("ShowPairingFilePicker"), object: nil)
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

func startTunnelInBackground(showErrorUI: Bool = true) {
    TunnelManager.shared.start(showErrorUI: showErrorUI)
}

func markTunnelDisconnected() {
    TunnelManager.shared.markDisconnected()
}

private func tunnelConnectionLogMessage(for error: NSError) -> String {
    let target = "\(DeviceConnectionContext.targetIPAddress):49152"
    return "Tunnel connection failed for \(target): \(error.localizedDescription) (Domain: \(error.domain), Code: \(error.code), Raw: \(String(describing: error)))"
}

private func tunnelConnectionAlertMessage(for error: NSError) -> String {
    let targetIP = DeviceConnectionContext.targetIPAddress
    let rawMessage = error.localizedDescription
    let lowercasedMessage = rawMessage.lowercased()

    let likelyCause: String
    let recoverySteps: [String]

    if error.code == 48 || lowercasedMessage.contains("address already in use") || lowercasedMessage.contains("port already in use") {
        likelyCause = "隧道所需的端口已被占用。"
        recoverySteps = [
            "关闭可能正在使用隧道的其它 JIT、调试、代理或 VPN 应用。",
            "断开并重新连接 LocalDevVPN。",
            "重启 StikDebug，然后重试。",
            "如果问题持续存在，请重启设备以清除被占用的端口。"
        ]
    } else if error.code == 54 || lowercasedMessage.contains("connection reset") {
        likelyCause = "设备或 VPN 在设置完成前关闭了隧道连接。"
        recoverySteps = [
            "打开 LocalDevVPN 并确认 VPN 已连接。",
            "确保 LocalDevVPN 使用默认地址 \(DeviceConnectionContext.defaultTargetIPAddress)。",
            "重新连接 Wi-Fi 和 LocalDevVPN，然后重试。",
            "如果问题持续存在，请选择新的配对文件。"
        ]
    } else if error.code == -18 || lowercasedMessage.contains("parse target ip") {
        likelyCause = "配置的目标 IP 地址无效。"
        recoverySteps = [
            "打开设置并检查目标 IP 地址。",
            "使用默认地址 \(DeviceConnectionContext.defaultTargetIPAddress)。"
        ]
    } else if lowercasedMessage.contains("timed out") || lowercasedMessage.contains("timeout") {
        likelyCause = "应用在连接超时前无法到达设备。"
        recoverySteps = [
            "确认 Wi-Fi 和 LocalDevVPN 均已连接。",
            "唤醒并解锁目标设备。",
            "确认 LocalDevVPN 在 \(targetIP) 开放设备访问。"
        ]
    } else if lowercasedMessage.contains("network is unreachable") || lowercasedMessage.contains("no route") {
        likelyCause = "到设备的 VPN 路由不可用。"
        recoverySteps = [
            "断开并重新连接 LocalDevVPN。",
            "确认 iOS 显示 VPN 指示器。",
            "尝试关闭并重新打开 Wi-Fi。"
        ]
    } else {
        likelyCause = "无法创建隧道。"
        recoverySteps = [
            "确认 Wi-Fi 和 LocalDevVPN 已连接。",
            "唤醒并解锁目标设备。",
            "重新连接 LocalDevVPN，然后重试。"
        ]
    }

    let steps = recoverySteps.enumerated()
        .map { "\($0.offset + 1). \($0.element)" }
        .joined(separator: "\n")

    return """
    \(likelyCause)

    目标: \(targetIP):49152
    预期的 LocalDevVPN IP: \(DeviceConnectionContext.defaultTargetIPAddress)

    请尝试：
    \(steps)

    技术详情：
    代码 \(error.code): \(rawMessage)
    """
}
