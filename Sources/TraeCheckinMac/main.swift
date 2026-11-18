import Cocoa

// 终端自检：只读账号与今日用量，不启动菜单栏 UI（便于排障 / CI）
if CommandLine.arguments.contains("--selftest") {
    let accounts = TraeClientCredentials.discover()
    print("发现账号: \(accounts.count)")
    for account in accounts {
        let exp = Date(timeIntervalSince1970: TimeInterval(account.jwtExp))
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        print("  uid=\(account.uid)  app=\(account.sourceApp)  jwt到期=\(formatter.string(from: exp))"
            + "  device=\(account.deviceID.isEmpty ? "-" : String(account.deviceID.suffix(6)))"
            + "  设备私钥=\(account.deviceKeyPEM.isEmpty ? "无" : "有")")
    }
    let today = CheckinStore.dayOf(Int64(Date().timeIntervalSince1970))
    for item in TraeUsage.today() {
        let status = item.ok ? "OK" : "FAIL(\(item.message))"
        var line = "  用量 uid=\(item.uid) \(status) 消耗=\(String(format: "%.2f", item.credits))"
        line += " 会话=\(item.sessions) token=\(item.tokens)"
        if let balance = item.balance { line += " 余额=\(String(format: "%.2f", balance))" }
        if let total = item.total { line += " 总额=\(String(format: "%.2f", total))" }
        print(line)
    }
    print("今日已签: \(accounts.filter { CheckinStore.shared.doneToday($0.uid, today) }.count)/\(accounts.count)")
    print("本地状态目录: \(CheckinStore.shared.dir.path)")
    exit(0)
}

// 纯菜单栏应用入口（LSUIElement，无 Dock 图标、无主窗口）
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
