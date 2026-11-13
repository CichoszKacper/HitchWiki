//
//  AuthManager.swift
//  HitchWise
//
//  Signing in is optional. Users sign in with Google only for now (no email/password);
//  Sign in with Apple comes later, once the app is in the Apple Developer Program.
//  Each signed-in user gets a profile in Firestore (users/{uid}, see UserService).
//  Also handles signing out and deleting the account, which the App Store requires.
//

import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class AuthManager {
    struct Account: Equatable {
        let uid: String
        let email: String?

        init(_ user: UserProtocol) {
            self.uid = user.uid
            self.email = user.email
        }
    }

    /// The signed-in user, nil when signed out.
    private(set) var account: Account?
    /// True while signing in, signing out or deleting; the buttons are disabled meanwhile.
    private(set) var isWorking = false
    /// Shown in an alert; cleared when the alert closes.
    var errorMessage: String?

    @ObservationIgnored private let auth: AuthServiceProtocol
    @ObservationIgnored private let userService: UserService
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HitchWise", category: "Auth")

    /// `nil` means the real Firebase services. Create this after `FirebaseApp.configure()`.
    init(auth: AuthServiceProtocol? = nil, userService: UserService? = nil) {
        self.auth = auth ?? FirebaseAuthService()
        self.userService = userService ?? .shared

        if let user = self.auth.currentUser {
            self.account = Account(user)
            // Firebase keeps users signed in, so also count opening the app as a login.
            self.updateProfileInBackground(user)
        }
        self.auth.listenForChanges { [weak self] user in
            Task { @MainActor in
                self?.account = user.map(Account.init)
            }
        }
    }

    // MARK: - Sign in with Google

    func signInWithGoogle() async {
        await self.run {
            let credential = try await self.googleCredential()
            try await self.signIn(with: credential)
        }
    }

    /// Google's sign-in sheet returns to the app through this URL.
    func handleOpenURL(_ url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Sign out

    func signOut() {
        do {
            try self.auth.signOut()
            GIDSignIn.sharedInstance.signOut()
            self.account = nil
            self.logger.info("Signed out")
        } catch {
            self.logger.error("Sign out failed: \(String(describing: error), privacy: .public)")
            self.errorMessage = Self.message(for: error)
        }
    }

    // MARK: - Delete account

    /// Deletes the profile in Firestore and the Firebase user.
    /// Firebase only deletes a user who signed in recently, so the user confirms with Google once more first.
    func deleteAccount() async {
        await self.run {
            guard let user = self.auth.currentUser else {
                return
            }
            self.logger.info("Deleting account \(user.uid)")
            try await user.reauthenticate(with: try await self.googleCredential())

            // Profile first, while still signed in (the rules only let the owner delete it).
            try await self.userService.deleteUserDocument(userID: user.uid)
            try await user.delete()
            try? await GIDSignIn.sharedInstance.disconnect()
            self.account = nil
            self.logger.info("Account deleted")
        }
    }

    // MARK: - Private

    private func signIn(with credential: AuthCredential) async throws {
        let user = try await self.auth.signIn(with: credential)
        self.logger.info("Signed in \(user.uid) with \(user.providerIDs.joined(separator: ", "), privacy: .public)")
        do {
            try await self.userService.createOrUpdateUserProfile(userID: user.uid, email: user.email)
        } catch {
            // Every signed-in user should have a profile, so don't stay signed in without one.
            self.logger.error("Couldn't save the profile: \(String(describing: error), privacy: .public)")
            try? self.auth.signOut()
            throw AuthFlowError.profileNotSaved
        }
        self.account = Account(user)
    }

    private func updateProfileInBackground(_ user: UserProtocol) {
        let uid = user.uid
        let email = user.email
        Task {
            do {
                try await self.userService.createOrUpdateUserProfile(userID: uid, email: email)
            } catch {
                self.logger.error("Couldn't update lastLoginAt: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Shows Google's sign-in sheet and turns the result into a Firebase credential.
    private func googleCredential() async throws -> AuthCredential {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            // GoogleService-Info.plist has no CLIENT_ID until Google sign-in is enabled in Firebase.
            throw AuthFlowError.googleNotConfigured
        }
        guard let presenter = UIApplication.shared.topViewController else {
            throw AuthFlowError.missingToken
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthFlowError.missingToken
        }
        return GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
    }

    /// Runs `work` with the buttons disabled and turns errors into a message (cancelling isn't an error).
    private func run(_ work: () async throws -> Void) async {
        guard !self.isWorking else {
            return
        }
        self.isWorking = true
        defer { self.isWorking = false }
        do {
            try await work()
        } catch {
            if Self.isCancellation(error) {
                self.logger.info("Cancelled by the user")
                return
            }
            self.logger.error("Auth failed: \(String(describing: error), privacy: .public)")
            self.errorMessage = Self.message(for: error)
        }
    }

    // MARK: - Errors

    enum AuthFlowError: LocalizedError {
        case missingToken
        case googleNotConfigured
        case profileNotSaved

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return String(localized: "Sign-in didn't finish. Please try again.", comment: "Auth error")
            case .googleNotConfigured:
                return String(localized: "Google sign-in isn't available yet.", comment: "Auth error")
            case .profileNotSaved:
                return String(localized: "Couldn't finish signing in. Please try again.", comment: "Auth error")
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if let error = error as? GIDSignInError, error.code == .canceled {
            return true
        }
        return false
    }

    static func message(for error: Error) -> String {
        if let error = error as? AuthFlowError {
            return error.errorDescription ?? error.localizedDescription
        }
        switch AuthErrorCode(_bridgedNSError: error as NSError)?.code {
        case .networkError:
            return String(localized: "Network error. Please check your connection and try again.", comment: "Auth error")
        case .tooManyRequests:
            return String(localized: "Too many attempts. Please try again later.", comment: "Auth error")
        case .userDisabled:
            return String(localized: "This account has been disabled.", comment: "Auth error")
        case .userMismatch:
            return String(localized: "Please confirm with the same account you're signed in with.", comment: "Auth error")
        case .requiresRecentLogin:
            return String(localized: "Please sign out, sign back in and try again.", comment: "Auth error")
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Previews

extension AuthManager {
    /// For SwiftUI previews, which don't run the app's init.
    static func forPreviews() -> AuthManager {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return AuthManager()
    }
}
