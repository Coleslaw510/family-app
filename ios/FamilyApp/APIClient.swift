import Foundation

struct APIError: Error, LocalizedError {
    enum Kind {
        case network
        case server
        case decoding
        case badURL
    }

    var message: String
    var unauthorized = false
    var kind: Kind = .server
    var errorDescription: String? { message }
}

extension Error {
    /// True for a request that was cancelled (for example a pull-to-refresh the system stopped),
    /// which is not a real failure and should never be shown to the user.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let url = self as? URLError, url.code == .cancelled { return true }
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}

final class APIClient {
    var baseURL: String = AppConfig.defaultServer
    var token: String?

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, data: nil)
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send("POST", path, data: nil)
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await send("POST", path, data: try Self.encode(body))
    }

    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await send("PATCH", path, data: try Self.encode(body))
    }

    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await send("PUT", path, data: try Self.encode(body))
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await send("DELETE", path, data: nil)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, data: Data?) async throws -> T {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let auth = token
        guard let url = URL(string: root + path) else {
            throw APIError(message: "That server URL doesn't look right.", kind: .badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let data {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let auth, !auth.isEmpty {
            request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        }
        let payload: Data
        let response: URLResponse
        do {
            (payload, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error.isCancellation { throw CancellationError() }
            throw APIError(message: Self.networkMessage(error), kind: .network)
        }
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(status) {
            throw APIError(message: Self.message(from: payload, status: status), unauthorized: status == 401)
        }
        if payload.isEmpty, let empty = JSONAck() as? T {
            return empty
        }
        do {
            return try Self.decoder.decode(T.self, from: payload)
        } catch {
            throw APIError(
                message: "Couldn't read the server response for \(Self.endpoint(path)): \(Self.decodeDetail(error))",
                kind: .decoding
            )
        }
    }

    private static func endpoint(_ path: String) -> String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    }

    private static func networkMessage(_ error: Error) -> String {
        guard let url = error as? URLError else {
            return "Network error: \(error.localizedDescription)"
        }
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "You're offline. Check your connection and pull to refresh."
        case .timedOut:
            return "The server took too long to answer. Try again."
        case .cannotFindHost, .dnsLookupFailed:
            return "Can't find the server. Check the address in Settings."
        case .cannotConnectToHost:
            return "The server isn't accepting connections right now."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return "Couldn't make a secure connection to the server (HTTPS certificate problem)."
        case .appTransportSecurityRequiresSecureConnection:
            return "The server address must start with https://."
        default:
            return "Network error (\(url.code.rawValue)): \(url.localizedDescription)"
        }
    }

    private static func decodeDetail(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        func location(_ path: [CodingKey]) -> String {
            let joined = path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
            return joined.isEmpty ? "the top level" : joined
        }
        switch decoding {
        case .keyNotFound(let key, let ctx):
            return "missing \"\(key.stringValue)\" at \(location(ctx.codingPath))."
        case .typeMismatch(_, let ctx):
            return "wrong type at \(location(ctx.codingPath)). \(ctx.debugDescription)"
        case .valueNotFound(_, let ctx):
            return "empty value at \(location(ctx.codingPath))."
        case .dataCorrupted(let ctx):
            return "bad data at \(location(ctx.codingPath)). \(ctx.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    /// Drop null keys so a partial update doesn't clear fields the screen didn't touch.
    private static func encode<Body: Encodable>(_ body: Body) throws -> Data {
        let data = try encoder.encode(body)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        for (key, value) in object where value is NSNull {
            object.removeValue(forKey: key)
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func message(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty { return detail }
            if let rows = object["detail"] as? [[String: Any]] {
                let parts = rows.compactMap { $0["msg"] as? String }
                if !parts.isEmpty { return parts.joined(separator: " ") }
            }
        }
        if status == 401 { return "Sign in again." }
        return "Something went wrong (\(status))."
    }
}
