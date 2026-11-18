import Foundation

// MARK: - 今日用量（只读）
//
//   POST /trae/api/v1/pay/query_user_usage_group_by_session  逐会话用量（token + credits）
//   POST /trae/api/v2/pay/ide_user_ent_usage                 积分总额 / 已用 / 余额
//
// 服务端分页上限：page_size 最大 20（>20 返回 9004），最多翻 50 页。

struct AccountUsage {
    let uid: String
    let app: String
    var ok: Bool = false
    var sessions: Int = 0
    var credits: Double = 0
    var tokens: Int = 0
    var consumed: Double?
    var total: Double?
    var balance: Double?
    var message: String = ""
}

enum TraeUsage {

    static let usagePath = "/trae/api/v1/pay/query_user_usage_group_by_session"
    static let entPath = "/trae/api/v2/pay/ide_user_ent_usage"
    static let pageSize = 20
    static let maxPages = 50

    /// 今日 00:00 → 此刻
    static func todayRange(now: Date = Date()) -> (Int64, Int64) {
        let start = Calendar.current.startOfDay(for: now)
        return (Int64(start.timeIntervalSince1970), Int64(now.timeIntervalSince1970))
    }

    /// 逐账号查询今日用量；JWT 过期先尝试 RT 续签
    static func today(now: Date = Date()) -> [AccountUsage] {
        let (start, end) = todayRange(now: now)
        return TraeClientCredentials.discover(now: now).map { account in
            var item = AccountUsage(uid: account.uid, app: account.sourceApp)
            var jwt = account.jwt
            if !TraeClientCredentials.jwtUsable(account, now: now) {
                guard let refreshed = TraeClientCredentials.refresh(account: account, now: now) else {
                    item.message = "JWT 已过期，请先打开 Trae 客户端"
                    return item
                }
                jwt = refreshed.jwt
            }
            let usage = fetchUsage(jwt: jwt, from: start, to: end)
            let ent = fetchEnt(jwt: jwt)
            item.ok = usage.error == nil
            item.sessions = usage.count
            item.credits = (usage.credits * 100).rounded() / 100
            item.tokens = usage.tokens
            item.message = usage.error ?? ""
            item.consumed = ent.consumed
            item.total = ent.total
            item.balance = ent.balance
            return item
        }
    }

    // MARK: 会话用量

    private static func fetchUsage(jwt: String, from: Int64, to: Int64)
        -> (count: Int, credits: Double, tokens: Int, error: String?) {
        var count = 0, tokens = 0
        var credits = 0.0
        var page = 1
        var total: Int?
        while page <= maxPages {
            let body = "{\"start_time\":\(from),\"end_time\":\(to),\"page_size\":\(pageSize),"
                + "\"page_num\":\(page),\"usage_type\":[7]}"
            let resp = HTTP.post(url: TraeCheckin.apiBase + usagePath, headers: [
                "authorization": "Cloud-IDE-JWT \(jwt)",
                "content-type": "application/json",
                "accept": "*/*",
            ], body: body)
            guard resp.status == 200, let data = resp.data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (count, credits, tokens, "无响应")
            }
            if let code = obj["code"] as? Int, code != 0 {
                return (count, credits, tokens, code == 1001 ? "会话失效" : "API code \(code)")
            }
            let sessions = obj["user_usage_group_by_sessions"] as? [[String: Any]] ?? []
            for session in sessions {
                count += 1
                credits += number(session["credits_float"]) ?? number(session["amount_float"]) ?? 0
                let extra = session["extra_info"] as? [String: Any] ?? [:]
                let gross = Int(number(extra["input_token"]) ?? 0)
                let cached = Int(number(extra["cache_read_token"]) ?? 0)
                tokens += max(0, gross - cached)
                tokens += Int(number(extra["output_token"]) ?? 0)
                tokens += cached
                tokens += Int(number(extra["cache_write_token"]) ?? 0)
            }
            total = Int(number(obj["total"]) ?? 0)
            if sessions.isEmpty || count >= (total ?? 0) { break }
            page += 1
        }
        return (count, credits, tokens, nil)
    }

    // MARK: 积分账单

    private static func fetchEnt(jwt: String) -> (consumed: Double?, total: Double?, balance: Double?) {
        let resp = HTTP.post(url: TraeCheckin.apiBase + entPath, headers: [
            "authorization": "Cloud-IDE-JWT \(jwt)",
            "content-type": "application/json",
            "accept": "*/*",
        ], body: "{\"require_usage\":true}")
        guard resp.status == 200, let data = resp.data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil)
        }
        let summary = obj["usage_summary"] as? [String: Any] ?? [:]
        return (number(summary["consumed_amount"]), number(summary["total_amount"]),
                number(obj["total_balance"]))
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
