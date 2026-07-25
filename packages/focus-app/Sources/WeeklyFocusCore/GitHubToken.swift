import Foundation
import Security

/// Resolves the GitHub token used to talk to the Brain Tasks board.
///
/// Lookup order:
/// 1. `BRAIN_GITHUB_TOKEN` / `GITHUB_TOKEN` environment variables.
/// 2. The macOS Keychain, using the same service/account that BrainOS writes to, so
///    the two apps share one credential once Weekly Focus folds into BrainOS.
/// 3. A one-time bootstrap from `gh auth token`, which is then cached in the Keychain.
///
/// The `gh` fallback exists only to seed the Keychain. The hot path never shells out.
public enum GitHubToken {
    public static let keychainService = "com.jonmagic.brainos.github"
    public static let keychainAccount = "github-token"

    public enum Failure: LocalizedError {
        case notFound

        public var errorDescription: String? {
            switch self {
            case .notFound:
                return """
                No GitHub token available. Set BRAIN_GITHUB_TOKEN, or run `gh auth login` \
                so Weekly Focus can seed the Keychain.
                """
            }
        }
    }

    public static func resolve() throws -> String {
        if let token = fromEnvironment() {
            return token
        }

        if let token = readKeychain() {
            return token
        }

        if let token = bootstrapFromGH() {
            writeKeychain(token)
            return token
        }

        throw Failure.notFound
    }

    static func fromEnvironment() -> String? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["BRAIN_GITHUB_TOKEN", "GITHUB_TOKEN"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        return nil
    }

    static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            return nil
        }

        return token
    }

    @discardableResult
    static func writeKeychain(_ token: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func bootstrapFromGH() -> String? {
        guard let executable = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "token"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            return nil
        }

        return token
    }
}
