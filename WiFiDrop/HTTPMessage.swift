import Foundation

/// 已解析的 HTTP 请求头信息（不含正文）。
struct HTTPRequestHead {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let contentLength: Int

    var isHeadRequest: Bool { method == "HEAD" }
}

/// 请求头解析错误。
enum HTTPParseError: Error {
    case malformed
}

/// 极简 HTTP/1.1 请求头解析器。
enum HTTPParser {
    /// 解析请求行与请求头，正文由连接层负责流式处理。
    static func parseHead(_ data: Data) throws -> HTTPRequestHead {
        guard let text = String(data: data, encoding: .utf8) else {
            throw HTTPParseError.malformed
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw HTTPParseError.malformed
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { throw HTTPParseError.malformed }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let split = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(split.first ?? "")
        let decodedPath = rawPath.removingPercentEncoding ?? rawPath

        var query: [String: String] = [:]
        if split.count > 1 {
            for pair in split[1].split(separator: "&", omittingEmptySubsequences: true) {
                let pairParts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let keyPart = pairParts.first else { continue }
                let key = String(keyPart).removingPercentEncoding ?? String(keyPart)
                var value = pairParts.count > 1 ? String(pairParts[1]) : ""
                value = value.replacingOccurrences(of: "+", with: " ")
                value = value.removingPercentEncoding ?? value
                query[key] = value
            }
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        return HTTPRequestHead(
            method: method,
            path: decodedPath,
            query: query,
            headers: headers,
            contentLength: contentLength
        )
    }
}

/// 可序列化为 HTTP/1.1 响应的结构。
struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data
    var sendBody: Bool
    var declaredLength: Int?

    init(status: Int,
         headers: [String: String] = [:],
         body: Data = Data(),
         sendBody: Bool = true,
         declaredLength: Int? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.sendBody = sendBody
        self.declaredLength = declaredLength
    }

    private static let reasonPhrases: [Int: String] = [
        200: "OK",
        204: "No Content",
        206: "Partial Content",
        400: "Bad Request",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        411: "Length Required",
        413: "Payload Too Large",
        431: "Request Header Fields Too Large",
        500: "Internal Server Error"
    ]

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    static func html(_ markup: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: Data(markup.utf8)
        )
    }

    static func text(_ message: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(message.utf8)
        )
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        .json(["ok": false, "error": message], status: status)
    }

    /// 生成完整的响应字节流。
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(HTTPResponse.reasonPhrases[status] ?? "OK")\r\n"
        var allHeaders = headers
        allHeaders["Server"] = "WiFiDrop"
        allHeaders["Connection"] = "close"
        allHeaders["Cache-Control"] = "no-store"
        allHeaders["Content-Length"] = String(declaredLength ?? body.count)
        for (key, value) in allHeaders {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        if sendBody {
            data.append(body)
        }
        return data
    }
}
