import Foundation

struct APIError: Error, LocalizedError {
    var message: String
    var unauthorized = false
    var errorDescription: String? { message }
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
            throw APIError(message: "That server URL doesn't look right.")
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
            throw APIError(message: "Can't reach the server. Check the address and try again.")
        }
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
            throw APIError(message: "Couldn't read the server response.")
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
