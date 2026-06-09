//
//  EMASServerlessClient.swift
//  EchoClock
//
//  Native Swift adapter for Alibaba Cloud EMAS Serverless RPC.
//

import CryptoKit
import Foundation

struct EMASConfig {
    static let spaceId = "mp-5d4f9564-c6dc-407b-9c57-f5260c7f09cd"
    static let clientSecret = "RAFj7jj26hC+NXblLwLvMA=="
    static let endpoint = URL(string: "https://api.next.bspapp.com/client")!
    static let bundleId = "mika.sha.EchoClock"

    static let loginFunctionTarget = "auth-login"
    static let registerFunctionTarget = "auth-register"
}

struct EMASAuthUser: Codable, Equatable {
    var id: String?
    var email: String?
    var displayName: String?
}

struct EMASAuthSession: Codable, Equatable {
    var token: String
    var user: EMASAuthUser
}

enum EMASAuthMode {
    case login
    case register
}

enum EMASClientError: LocalizedError {
    case invalidResponse
    case missingSession
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "EMAS 返回格式无法解析"
        case .missingSession:
            return "登录成功响应中缺少 token 或用户信息"
        case .serverMessage(let message):
            return message
        }
    }
}

final class EMASServerlessClient {
    static let shared = EMASServerlessClient()

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func login(email: String, password: String) async throws -> EMASAuthSession {
        try await authenticate(mode: .login, email: email, password: password)
    }

    func register(email: String, password: String) async throws -> EMASAuthSession {
        try await authenticate(mode: .register, email: email, password: password)
    }

    private func authenticate(mode: EMASAuthMode, email: String, password: String) async throws -> EMASAuthSession {
        let target = mode == .login ? EMASConfig.loginFunctionTarget : EMASConfig.registerFunctionTarget
        let result = try await invokeFunction(
            target: target,
            arguments: [
                "email": email,
                "password": password,
                "bundleId": EMASConfig.bundleId,
                "platform": "ios"
            ]
        )
        return try parseAuthSession(from: result, fallbackEmail: email)
    }

    func invokeFunction(target: String, arguments: [String: Any]) async throws -> [String: Any] {
        let params: [String: Any] = [
            "functionTarget": target,
            "functionArgs": arguments
        ]
        return try await sendRPC(method: "serverless.function.runtime.invoke", params: params)
    }

    private func sendRPC(method: String, params: [String: Any]) async throws -> [String: Any] {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let paramsJSON = try canonicalJSONString(params)
        let body: [String: Any] = [
            "spaceId": EMASConfig.spaceId,
            "timestamp": timestamp,
            "method": method,
            "params": paramsJSON
        ]

        var request = URLRequest(url: EMASConfig.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("pkg_name:EchoClock-iOS;ver:1.0;", forHTTPHeaderField: "x-serverless-ua")
        request.setValue(signature(method: method, paramsJSON: paramsJSON, timestamp: timestamp), forHTTPHeaderField: "x-serverless-sign")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EMASClientError.invalidResponse
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EMASClientError.invalidResponse
        }

        if let message = object["message"] as? String,
           let success = object["success"] as? Bool,
           !success {
            throw EMASClientError.serverMessage(message)
        }
        if let error = object["error"] as? String {
            throw EMASClientError.serverMessage(error)
        }
        if let body = object["body"] as? [String: Any] {
            return body
        }
        if let result = object["result"] as? [String: Any] {
            return result
        }
        return object
    }

    private func signature(method: String, paramsJSON: String, timestamp: Int) -> String {
        let stringToSign = [
            "method=\(method)",
            "params=\(paramsJSON)",
            "spaceId=\(EMASConfig.spaceId)",
            "timestamp=\(timestamp)"
        ].joined(separator: "&")
        let key = SymmetricKey(data: Data(EMASConfig.clientSecret.utf8))
        let digest = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func canonicalJSONString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func parseAuthSession(from object: [String: Any], fallbackEmail: String) throws -> EMASAuthSession {
        let candidates = [
            object,
            object["result"] as? [String: Any],
            object["data"] as? [String: Any],
            object["body"] as? [String: Any]
        ].compactMap { $0 }

        for candidate in candidates {
            let token = candidate["token"] as? String
                ?? candidate["accessToken"] as? String
                ?? candidate["sessionToken"] as? String
            guard let token, !token.isEmpty else { continue }

            let userObject = candidate["user"] as? [String: Any]
                ?? candidate["profile"] as? [String: Any]
                ?? candidate
            let user = EMASAuthUser(
                id: userObject["id"] as? String ?? userObject["userId"] as? String ?? userObject["uid"] as? String,
                email: userObject["email"] as? String ?? fallbackEmail,
                displayName: userObject["displayName"] as? String ?? userObject["nickname"] as? String
            )
            return EMASAuthSession(token: token, user: user)
        }

        throw EMASClientError.missingSession
    }
}
