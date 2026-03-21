import Foundation

/// Lightweight Supabase REST client (no external dependencies)
class SupabaseClient {
    static let shared = SupabaseClient()

    // Configure these with your Supabase project values
    @AppStorage("supabaseURL") private var supabaseURL: String = ""
    @AppStorage("supabaseAnonKey") private var supabaseAnonKey: String = ""

    private var accessToken: String?

    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    private init() {
        // Restore session from Keychain
        if let token = KeychainManager.shared.getAPIKey(for: .supabase) {
            accessToken = token
        }
    }

    // MARK: - Configuration

    func configure(url: String, anonKey: String) {
        supabaseURL = url
        supabaseAnonKey = anonKey
        NSLog("[Supabase] Configured: %@", url)
    }

    // MARK: - Auth

    func setSession(accessToken: String) {
        self.accessToken = accessToken
        KeychainManager.shared.saveAPIKey(accessToken, for: .supabase)
    }

    func clearSession() {
        accessToken = nil
        KeychainManager.shared.deleteAPIKey(for: .supabase)
    }

    // MARK: - REST API

    func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard isConfigured else { throw SupabaseError.notConfigured }

        guard let url = URL(string: "\(supabaseURL)\(path)") else {
            throw SupabaseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }

        return (data, httpResponse)
    }

    // MARK: - Edge Functions

    func invokeFunction(
        name: String,
        body: [String: Any]
    ) async throws -> Data {
        guard isConfigured else { throw SupabaseError.notConfigured }

        guard let url = URL(string: "\(supabaseURL)/functions/v1/\(name)") else {
            throw SupabaseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw SupabaseError.rateLimited(error)
            }
            throw SupabaseError.rateLimited("Rate limit exceeded")
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.serverError(httpResponse.statusCode, message)
        }

        return data
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case serverError(Int, String)
    case rateLimited(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase is not configured"
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .rateLimited(let msg): return msg
        case .notAuthenticated: return "Not authenticated"
        }
    }
}

import SwiftUI
