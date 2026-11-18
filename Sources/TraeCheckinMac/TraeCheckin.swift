import Foundation
import CryptoKit

// MARK: - Trae 每日签到引擎
//
// 2026-11 实证：签到接口（checkin_credits/status|claim）一直可用；此前 1001 +
// enable:false 是 sessionid 链 JWT 鉴权等级不够被拒，客户端源 JWT 直接通过。
// 请求须带完整客户端形态请求头（VSCode UA + x-lscbd-aid + package-type 等）。
//
// 奖励金额取 status 的 credits + extra_credits：claim 成功响应只有
// {"code":0,"message":"success"}，不带金额；真实"今日已签"标志是 did_checked_in。

struct TraeCheckinStatus: Equatable {
    let enable: Bool
    let checkedIn: Bool
    let credits: Double
    let extraCredits: Double
    let code: Int?
    let message: String
}

struct TraeCheckinClaim {
    let ok: Bool
    let code: Int?
    let message: String
    /// 服务端返回「今日已经签到」：本次没有真正领取，不应再记一笔奖励
    var already: Bool = false
}

enum TraeCheckin {

    static let apiBase = "https://api.trae.cn"
    static let statusPath = "/trae/api/v2/ug/checkin_credits/status"
    static let claimPath = "/trae/api/v2/ug/checkin_credits/claim"

    /// 签到网关要求的完整客户端形态请求头（缺头会被 1001 + enable:false 拒绝）。
    /// x-device-id 用本机客户端真实设备号；market_user_id / vscode-sessionid 按
    /// uid 确定性派生（同账号恒定，跨启动稳定）。
    static func headers(jwt: String, uid: String, deviceID: String) -> [String: String] {
        func seeded(_ seed: String, _ n: Int) -> [UInt8] {
            var out: [UInt8] = []
            var counter = 0
            while out.count < n {
                let digest = CryptoKit.SHA512.hash(data: Data("\(uid):\(seed):\(counter)".utf8))
                out.append(contentsOf: digest.withUnsafeBytes { Array($0) })
                counter += 1
            }
            return Array(out[0..<n])
        }
        let session = seeded("sess", 32).map { String(format: "%02x", $0) }.joined()
        var m = seeded("market", 16)
        m[6] = (m[6] & 0x0F) | 0x40   // UUID v4 版本位
        m[8] = (m[8] & 0x3F) | 0x80   // UUID v4 变体位
        let hex = m.map { String(format: "%02x", $0) }.joined()
        let marketUID = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-"
            + "\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))"
            + "-\(hex.dropFirst(20))"
        let trace = (0..<8).map { _ in UInt8.random(in: 0...255) }
            .map { String(format: "%02x", $0) }.joined()
        let requestID = (0..<16).map { _ in UInt8.random(in: 0...255) }
            .map { String(format: "%02x", $0) }.joined()
        return [
            "accept": "*/*",
            "accept-language": "zh-CN",
            "authorization": "Cloud-IDE-JWT \(jwt)",
            "content-type": "application/json",
            "user-agent": "VSCode 1.107.1 (TRAE SOLO CN)",
            "x-market-client-id": "VSCode 1.107.1",
            "x-market-user-id": marketUID,
            "x-user-region": "CN",
            "x-device-id": deviceID,
            "x-lgw-req-sdk-type": "3",
            "package-type": "stable_cn",
            "x-request-id": requestID,
            "x-lscbd-aid": "787976",
            "x-lscbd-platform": "windows",
            "app-version": "0.1.45",
            "x-tt-trace-id": "00-\(trace)-01",
            "vscode-sessionid": session,
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "no-cors",
            "sec-fetch-site": "none",
        ]
    }

    /// 预检今日是否已签
    static func status(jwt: String, uid: String, deviceID: String) -> TraeCheckinStatus {
        let resp = HTTP.post(url: apiBase + statusPath,
                             headers: headers(jwt: jwt, uid: uid, deviceID: deviceID), body: "{}")
        return parse(resp.data, fallbackMessage: "无响应")
    }

    /// 领取签到奖励（金额在 status 里，claim 响应不带）
    static func claim(jwt: String, uid: String, deviceID: String) -> TraeCheckinClaim {
        let resp = HTTP.post(url: apiBase + claimPath,
                             headers: headers(jwt: jwt, uid: uid, deviceID: deviceID), body: "{}")
        guard let data = resp.data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TraeCheckinClaim(ok: false, code: nil, message: "无响应")
        }
        let code = obj["code"] as? Int
        let message = obj["message"] as? String ?? ""
        let already = message.contains("已经签到") || message.contains("already checked in")
        let authRejected = message.lowercased().contains("not able to authenticate")
        let ok = (code == 0 || code == nil) && !authRejected
        return TraeCheckinClaim(ok: ok || already, code: code, message: message, already: already)
    }

    /// 当天签到分钟（0–59）：按账号 + 日期确定性派生，重启不会重掷
    static func slotMinute(uid: String, day: String) -> Int {
        let digest = SHA256.hash(data: Data("\(uid):\(day)".utf8))
        let head = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Int(head % 60)
    }

    private static func parse(_ data: Data?, fallbackMessage: String) -> TraeCheckinStatus {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TraeCheckinStatus(enable: false, checkedIn: false, credits: 0,
                                     extraCredits: 0, code: nil, message: fallbackMessage)
        }
        // 真实"今日已签"标志是 did_checked_in（见过 checked_in=false + did_checked_in=true）
        let checkedIn = (obj["checked_in"] as? Bool) ?? false
        let didCheckedIn = (obj["did_checked_in"] as? Bool) ?? false
        return TraeCheckinStatus(
            enable: (obj["enable"] as? Bool) ?? false,
            checkedIn: checkedIn || didCheckedIn,
            credits: (obj["credits"] as? Double) ?? ((obj["credits"] as? Int).map(Double.init)) ?? 0,
            extraCredits: (obj["extra_credits"] as? Double)
                ?? ((obj["extra_credits"] as? Int).map(Double.init)) ?? 0,
            code: obj["code"] as? Int,
            message: obj["message"] as? String ?? "")
    }
}
