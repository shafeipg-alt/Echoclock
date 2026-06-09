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

    static let phoneCodeLoginFunctionTarget = "auth-phone-code-login"
    static let passwordLoginFunctionTarget = "auth-password-login"
    static let passwordRegisterFunctionTarget = "auth-password-register"
    static let wechatLoginFunctionTarget = "auth-wechat-login"
    static let smsCodeFunctionTarget = "auth-send-sms-code"
}

struct EMASAuthUser: Codable, Equatable {
    var id: String?
    var email: String?
    var phone: String?
    var displayName: String?
}

struct EMASAuthSession: Codable, Equatable {
    var token: String
    var user: EMASAuthUser
}

enum EMASAuthMode {
    case phoneCodeLogin
    case passwordLogin
    case passwordRegister
    case wechatLogin
}

enum EMASClientError: LocalizedError {
    case invalidResponse
    case missingSession
    case wechatUnavailable(String)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "EMAS 返回格式无法解析"
        case .missingSession:
            return "登录服务未返回有效登录态，请检查云函数是否返回 token"
        case .wechatUnavailable(let message):
            return message
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

    func sendSMSCode(phone: String) async throws {
        _ = try await invokeFunction(
            target: EMASConfig.smsCodeFunctionTarget,
            arguments: baseArguments([
                "phone": phone
            ])
        )
    }

    func loginWithCode(phone: String, code: String) async throws -> EMASAuthSession {
        let result = try await invokeFunction(
            target: EMASConfig.phoneCodeLoginFunctionTarget,
            arguments: baseArguments([
                "phone": phone,
                "code": code
            ])
        )
        return try parseAuthSession(from: result, fallbackPhone: phone)
    }

    func loginWithPassword(phone: String, password: String) async throws -> EMASAuthSession {
        let result = try await invokeFunction(
            target: EMASConfig.passwordLoginFunctionTarget,
            arguments: baseArguments([
                "phone": phone,
                "password": password
            ])
        )
        return try parseAuthSession(from: result, fallbackPhone: phone)
    }

    func registerWithPassword(phone: String, password: String, code: String?) async throws -> EMASAuthSession {
        var arguments: [String: Any] = [
            "phone": phone,
            "password": password
        ]
        if let code, !code.isEmpty {
            arguments["code"] = code
        }

        let result = try await invokeFunction(
            target: EMASConfig.passwordRegisterFunctionTarget,
            arguments: baseArguments(arguments)
        )
        return try parseAuthSession(from: result, fallbackPhone: phone)
    }

    func loginWithWeChat() async throws -> EMASAuthSession {
        let result = try await invokeFunction(
            target: EMASConfig.wechatLoginFunctionTarget,
            arguments: baseArguments([
                "provider": "wechat",
                "providerName": "微信",
                "authCode": NSNull(),
                "message": "iOS WeChat SDK is not linked yet. The cloud function should return a test token or guide binding WeChat SDK auth code."
            ])
        )
        do {
            return try parseAuthSession(from: result, fallbackPhone: nil)
        } catch {
            let message = readableMessage(from: result)
                ?? "微信登录服务未配置：请在云函数 auth-wechat-login 中返回 token，或先接入微信开放平台 SDK 获取 authCode。"
            throw EMASClientError.wechatUnavailable(message)
        }
    }

    private func baseArguments(_ arguments: [String: Any]) -> [String: Any] {
        var merged = arguments
        merged["bundleId"] = EMASConfig.bundleId
        merged["platform"] = "ios"
        return merged
    }

    private func authenticate(mode: EMASAuthMode, phone: String, password: String? = nil, code: String? = nil) async throws -> EMASAuthSession {
        switch mode {
        case .phoneCodeLogin:
            return try await loginWithCode(phone: phone, code: code ?? "")
        case .passwordLogin:
            return try await loginWithPassword(phone: phone, password: password ?? "")
        case .passwordRegister:
            return try await registerWithPassword(phone: phone, password: password ?? "", code: code)
        case .wechatLogin:
            return try await loginWithWeChat()
        }
    }

    @available(*, deprecated, message: "Use phone-based auth methods instead.")
    func login(email: String, password: String) async throws -> EMASAuthSession {
        let result = try await invokeFunction(
            target: EMASConfig.passwordLoginFunctionTarget,
            arguments: baseArguments([
                "email": email,
                "password": password,
            ])
        )
        return try parseAuthSession(from: result, fallbackEmail: email)
    }

    @available(*, deprecated, message: "Use phone-based auth methods instead.")
    func register(email: String, password: String) async throws -> EMASAuthSession {
        let result = try await invokeFunction(
            target: EMASConfig.passwordRegisterFunctionTarget,
            arguments: baseArguments([
                "email": email,
                "password": password,
            ])
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
        return unwrapResponse(object)
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

    private func parseAuthSession(from object: [String: Any], fallbackEmail: String? = nil, fallbackPhone: String? = nil) throws -> EMASAuthSession {
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
                phone: userObject["phone"] as? String ?? userObject["mobile"] as? String ?? fallbackPhone,
                displayName: userObject["displayName"] as? String ?? userObject["nickname"] as? String
            )
            return EMASAuthSession(token: token, user: user)
        }

        throw EMASClientError.missingSession
    }

    private func unwrapResponse(_ object: [String: Any]) -> [String: Any] {
        if let body = object["body"] as? [String: Any] {
            if let result = body["result"] as? [String: Any] {
                return result
            }
            if let data = body["data"] as? [String: Any] {
                return data
            }
            return body
        }
        if let result = object["result"] as? [String: Any] {
            return result
        }
        if let data = object["data"] as? [String: Any] {
            return data
        }
        return object
    }

    private func readableMessage(from object: [String: Any]) -> String? {
        let candidates = [
            object,
            object["result"] as? [String: Any],
            object["data"] as? [String: Any],
            object["body"] as? [String: Any]
        ].compactMap { $0 }

        for candidate in candidates {
            if let message = candidate["message"] as? String, !message.isEmpty {
                return message
            }
            if let message = candidate["msg"] as? String, !message.isEmpty {
                return message
            }
            if let error = candidate["error"] as? String, !error.isEmpty {
                return error
            }
        }
        return nil
    }
}
