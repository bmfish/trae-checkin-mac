import Foundation

// MARK: - 本地状态（与 Windows 版共用同一套 JSON 结构）
//
// ~/.trae-checkin/state.json
//   done  { uid: "YYYY-MM-DD" }   已签水位
//   fail  { uid: epoch }          上次失败时间（1 小时内不重试）
//   log   [ {t, uid, ok, credits, msg} ]  最近 100 条
// ~/.trae-checkin/checkin.log     追加式文本日志

struct CheckinRecord {
    let t: Int64
    let uid: String
    let ok: Bool
    let credits: Double
    let msg: String

    var dict: [String: Any] {
        ["t": t, "uid": uid, "ok": ok, "credits": credits, "msg": msg]
    }

    init?(dict: [String: Any]) {
        guard let uid = dict["uid"] as? String else { return nil }
        t = Int64((dict["t"] as? NSNumber)?.int64Value ?? 0)
        self.uid = uid
        ok = (dict["ok"] as? Bool) ?? false
        credits = (dict["credits"] as? NSNumber)?.doubleValue ?? 0
        msg = dict["msg"] as? String ?? ""
    }

    init(t: Int64, uid: String, ok: Bool, credits: Double, msg: String) {
        self.t = t; self.uid = uid; self.ok = ok; self.credits = credits; self.msg = msg
    }
}

final class CheckinStore {

    static let shared = CheckinStore()

    let dir: URL
    private let statePath: URL
    private let logPath: URL
    private let queue = DispatchQueue(label: "trae-checkin.store")
    private var state: [String: Any] = [:]

    init(directory: URL? = nil) {
        let override = ProcessInfo.processInfo.environment["TRAE_CHECKIN_HOME"]
        if let directory {
            dir = directory
        } else if let override, !override.isEmpty {
            dir = URL(fileURLWithPath: override)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".trae-checkin")
        }
        statePath = dir.appendingPathComponent("state.json")
        logPath = dir.appendingPathComponent("checkin.log")
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: statePath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            state = obj
        } else {
            state = [:]
        }
        state["done"] = state["done"] as? [String: Any] ?? [:]
        state["fail"] = state["fail"] as? [String: Any] ?? [:]
        state["log"] = state["log"] as? [Any] ?? []
    }

    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: state,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: statePath, options: .atomic)
    }

    // MARK: 水位

    func doneToday(_ uid: String, _ day: String) -> Bool {
        queue.sync { ((state["done"] as? [String: Any])?[uid] as? String) == day }
    }

    func markDone(_ uid: String, _ day: String) {
        queue.sync {
            var done = state["done"] as? [String: Any] ?? [:]
            done[uid] = day
            state["done"] = done
            var fail = state["fail"] as? [String: Any] ?? [:]
            fail.removeValue(forKey: uid)
            state["fail"] = fail
            save()
        }
    }

    func failAt(_ uid: String) -> Int64 {
        queue.sync {
            Int64(((state["fail"] as? [String: Any])?[uid] as? NSNumber)?.int64Value ?? 0)
        }
    }

    func markFail(_ uid: String, _ epoch: Int64) {
        queue.sync {
            var fail = state["fail"] as? [String: Any] ?? [:]
            fail[uid] = epoch
            state["fail"] = fail
            save()
        }
    }

    // MARK: 记录

    func appendLog(_ uid: String, ok: Bool, credits: Double, msg: String, epoch: Int64) {
        let record = CheckinRecord(t: epoch, uid: uid, ok: ok, credits: credits, msg: msg)
        queue.sync {
            var log = state["log"] as? [Any] ?? []
            log.append(record.dict)
            if log.count > 100 { log.removeFirst(log.count - 100) }
            state["log"] = log
            save()
            writeText(record)
        }
    }

    /// 今日成功记录只写一笔；已有记录且金额为空时补金额
    func recordOnce(_ uid: String, _ day: String, credits: Double, msg: String, epoch: Int64) {
        if loggedToday(uid, day) {
            fixup(uid, day, credits)
        } else {
            appendLog(uid, ok: true, credits: credits, msg: msg, epoch: epoch)
        }
    }

    private func fixup(_ uid: String, _ day: String, _ credits: Double) {
        guard credits > 0 else { return }
        queue.sync {
            var log = state["log"] as? [Any] ?? []
            for index in log.indices.reversed() {
                guard let dict = log[index] as? [String: Any],
                      let rec = CheckinRecord(dict: dict), rec.ok, rec.uid == uid,
                      Self.dayOf(rec.t) == day else { continue }
                if rec.credits == 0 {
                    log[index] = CheckinRecord(t: rec.t, uid: uid, ok: true,
                                               credits: credits, msg: rec.msg).dict
                    state["log"] = log
                    save()
                }
                break
            }
        }
    }

    func loggedToday(_ uid: String, _ day: String) -> Bool {
        queue.sync {
            let log = state["log"] as? [Any] ?? []
            return log.contains { item in
                guard let dict = item as? [String: Any], let rec = CheckinRecord(dict: dict) else { return false }
                return rec.ok && rec.uid == uid && Self.dayOf(rec.t) == day
            }
        }
    }

    func todayCredits(_ day: String) -> Double {
        queue.sync {
            let log = state["log"] as? [Any] ?? []
            return log.reduce(0.0) { sum, item in
                guard let dict = item as? [String: Any], let rec = CheckinRecord(dict: dict) else { return sum }
                return rec.ok && Self.dayOf(rec.t) == day ? sum + rec.credits : sum
            }
        }
    }

    func recent(_ limit: Int = 5) -> [CheckinRecord] {
        queue.sync {
            let log = (state["log"] as? [Any] ?? []).compactMap {
                ($0 as? [String: Any]).flatMap(CheckinRecord.init(dict:))
            }
            return Array(log.suffix(limit).reversed())
        }
    }

    private func writeText(_ record: CheckinRecord) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(record.t)))
        let amount = record.credits > 0 ? String(format: "+%g", record.credits) : "-"
        let line = "\(stamp)\tuid=\(record.uid)\t\(record.ok ? "OK" : "FAIL")\t\(amount)\t\(record.msg)\n"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logPath) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: logPath)
        }
    }

    static func dayOf(_ epoch: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}

// MARK: - 一轮签到

enum CheckinRunner {

    enum Action: String {
        case done, already, skipped, failed
    }

    struct Result {
        let uid: String
        let action: Action
        let message: String
        let credits: Double
    }

    static let failCooldown: TimeInterval = 3600

    /// 执行一轮签到。force=true 忽略随机分钟门与失败冷却（手动签到）。
    @discardableResult
    static func runOnce(force: Bool, startHour: Int, now: Date = Date(),
                        store: CheckinStore = .shared) -> [Result] {
        let accounts = TraeClientCredentials.discover(now: now)
        guard !accounts.isEmpty else { return [] }
        let epoch = Int64(now.timeIntervalSince1970)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        let dayStart = Int64(Calendar.current.startOfDay(for: now).timeIntervalSince1970)
        var results: [Result] = []
        for account in accounts {
            results.append(checkin(account, store: store, epoch: epoch, dayStart: dayStart,
                                   today: today, force: force, startHour: startHour))
        }
        return results
    }

    private static func checkin(_ account: ClientTraeAccount, store: CheckinStore,
                                epoch: Int64, dayStart: Int64, today: String,
                                force: Bool, startHour: Int) -> Result {
        // 1) 本地水位：今日已签彻底跳过，连 status 都不请求
        if store.doneToday(account.uid, today) {
            return Result(uid: account.uid, action: .skipped, message: "今日已签", credits: 0)
        }
        // 2) 随机分钟门：起始小时 + 账号当天派生分钟
        let slot = dayStart + Int64(startHour * 3600)
            + Int64(TraeCheckin.slotMinute(uid: account.uid, day: today) * 60)
        if !force && epoch < slot {
            let text = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(slot)),
                                                     dateStyle: .none, timeStyle: .short)
            return Result(uid: account.uid, action: .skipped, message: "未到签到时间 \(text)", credits: 0)
        }
        // 3) 失败冷却
        if !force && epoch - store.failAt(account.uid) < Int64(failCooldown) {
            return Result(uid: account.uid, action: .skipped, message: "失败冷却中", credits: 0)
        }
        // 4) JWT 过期先尝试 RT 续签
        var jwt = account.jwt
        if !TraeClientCredentials.jwtUsable(account) {
            guard let refreshed = TraeClientCredentials.refresh(account: account) else {
                return Result(uid: account.uid, action: .skipped, message: "JWT 已过期且无法续签", credits: 0)
            }
            jwt = refreshed.jwt
        }
        // 5) 服务端状态判定
        let st = TraeCheckin.status(jwt: jwt, uid: account.uid, deviceID: account.deviceID)
        if st.code == 0 && !st.checkedIn && !st.enable {
            return Result(uid: account.uid, action: .skipped, message: "活动未开启", credits: 0)
        }
        if st.code != 0 && !st.checkedIn {
            store.appendLog(account.uid, ok: false, credits: 0,
                            msg: st.message, epoch: epoch)
            store.markFail(account.uid, epoch)
            return Result(uid: account.uid, action: .failed,
                          message: st.message.isEmpty ? "状态查询失败" : st.message, credits: 0)
        }
        let reward = st.credits + st.extraCredits
        if st.checkedIn {
            store.markDone(account.uid, today)
            store.recordOnce(account.uid, today, credits: reward,
                             msg: st.message.isEmpty ? "今日已签" : st.message, epoch: epoch)
            return Result(uid: account.uid, action: .already,
                          message: st.message.isEmpty ? "今日已签" : st.message, credits: reward)
        }
        // 6) claim 前再核一次水位
        if store.doneToday(account.uid, today) {
            return Result(uid: account.uid, action: .skipped, message: "今日已签", credits: 0)
        }
        let claim = TraeCheckin.claim(jwt: jwt, uid: account.uid, deviceID: account.deviceID)
        if claim.ok {
            store.markDone(account.uid, today)
            store.recordOnce(account.uid, today, credits: reward,
                             msg: claim.message.isEmpty ? "今日已签" : claim.message, epoch: epoch)
            return Result(uid: account.uid, action: claim.already ? .already : .done,
                          message: claim.message.isEmpty ? "success" : claim.message, credits: reward)
        }
        store.appendLog(account.uid, ok: false, credits: 0,
                        msg: claim.message, epoch: epoch)
        store.markFail(account.uid, epoch)
        return Result(uid: account.uid, action: .failed,
                      message: claim.message.isEmpty ? "签到失败" : claim.message, credits: 0)
    }
}
