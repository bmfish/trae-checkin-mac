import Foundation

/// 最小 HTTP 客户端：只需要 POST（签到 / 用量全部是 POST JSON）
struct HTTPResponse {
    let status: Int
    let data: Data?
}

enum HTTP {
    static func post(url: String, headers: [String: String] = [:],
                     body: String = "{}", timeout: TimeInterval = 20) -> HTTPResponse {
        guard let target = URL(string: url) else { return HTTPResponse(status: 0, data: nil) }
        var req = URLRequest(url: target)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.httpBody = Data(body.utf8)
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        guard let (data, resp) = try? URLSession.shared.syncData(with: req) else {
            return HTTPResponse(status: 0, data: nil)
        }
        return HTTPResponse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }
}

extension URLSession {
    /// 同步请求（调用方都在后台队列，避免回调里处理 UI 状态）
    func syncData(with request: URLRequest) throws -> (Data, URLResponse?) {
        var result: Result<(Data, URLResponse?), Error>!
        let semaphore = DispatchSemaphore(value: 0)
        dataTask(with: request) { data, resp, err in
            if let err { result = .failure(err) }
            else { result = .success((data ?? Data(), resp)) }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }
}
