import Foundation
import Combine

// MARK: - 界面状态（对应 Windows 版 main.py 的 render / update_sign_button / load_usage）

final class UsageModel: ObservableObject {

    @Published var accounts: [ClientTraeAccount] = []
    @Published var usage: [AccountUsage] = []
    @Published var loaded = false
    @Published var busy = false
    @Published var signing = false
    @Published var tip = ""
    @Published var note = "签到：未发现客户端账号"
    @Published var startHour: Int = 9
    @Published var autostart: Bool = LoginItem.isEnabled
    @Published var windowHeight: CGFloat = 420
    /// 全部账号已签时禁用按钮
    @Published var allSigned = false
    /// 今日已签账号
    @Published var signedUIDs: Set<String> = []

    private let store = CheckinStore.shared
    private let work = DispatchQueue(label: "trae-checkin.work", qos: .utility)

    init() {
        if let value = UserDefaults.standard.object(forKey: "startHour") as? Int {
            startHour = min(23, max(0, value))
        }
    }

    static func today() -> String {
        CheckinStore.dayOf(Int64(Date().timeIntervalSince1970))
    }

    // MARK: 刷新用量

    func refresh() {
        guard !busy else { return }
        busy = true
        tip = "查询中…"
        work.async { [weak self] in
            guard let self else { return }
            let accounts = TraeClientCredentials.discover()
            let usage = TraeUsage.today()
            let error = usage.first(where: { !$0.ok })?.message ?? ""
            DispatchQueue.main.async {
                self.busy = false
                self.loaded = true
                self.accounts = accounts
                self.usage = usage
                self.tip = error.isEmpty
                    ? "更新于 " + Self.clock()
                    : "查询失败：\(error)"
                self.recompute()
            }
        }
    }

    // MARK: 立即签到

    func checkin() {
        guard !signing else { return }
        signing = true
        allSigned = false
        let hour = startHour
        work.async { [weak self] in
            guard let self else { return }
            CheckinRunner.runOnce(force: true, startHour: hour)
            DispatchQueue.main.async {
                self.signing = false
                self.refresh()
            }
        }
    }

    // MARK: 签到汇总 / 窗口高度

    private func recompute() {
        let today = Self.today()
        let signed = accounts.filter { store.doneToday($0.uid, today) }.count
        signedUIDs = Set(accounts.filter { store.doneToday($0.uid, today) }.map(\.uid))
        let gained = store.todayCredits(today)
        allSigned = !accounts.isEmpty && signed >= accounts.count

        if accounts.isEmpty {
            note = "签到：未发现客户端账号"
        } else {
            var text = "签到：\(signed)/\(accounts.count) 已签"
            if gained > 0 { text += " · 今日获得 +\(Self.money(gained)) 积分" }
            let slots = accounts.filter { !store.doneToday($0.uid, today) }.map {
                String(format: "%02d:%02d", startHour, TraeCheckin.slotMinute(uid: $0.uid, day: today))
            }
            if !slots.isEmpty { text += " · 今天 \(slots.joined(separator: " / ")) 自动签" }
            note = text
        }
        // 窗口高度贴合内容：单账号 420，每多一个账号 +200，最高 780
        windowHeight = accounts.isEmpty
            ? 380
            : min(max(420 + CGFloat(accounts.count - 1) * 200, 420), 780)
    }

    // MARK: 设置

    func setStartHour(_ hour: Int) {
        startHour = min(23, max(0, hour))
        UserDefaults.standard.set(startHour, forKey: "startHour")
        tip = "已保存：\(startHour) 点后随机一分钟自动签到"
        recompute()
    }

    func toggleAutostart() {
        if let error = LoginItem.setEnabled(!LoginItem.isEnabled) {
            tip = "自启设置失败：\(error)"
        }
        autostart = LoginItem.isEnabled
    }

    // MARK: 格式化（与 Windows 版一致）

    static func money(_ value: Double) -> String { String(format: "%.2f", value) }

    static func clock() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    static func dateText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
