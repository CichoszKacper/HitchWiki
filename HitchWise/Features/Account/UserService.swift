//
//  UserService.swift
//  HitchWise
//
//  Reads and writes the user's profile in Firestore (users/{uid}).
//  Unlike Fault Navigator, where admins create profiles, the profile is created here on first sign-in.
//

import Foundation
import FirebaseFirestore

final class UserService {
    static let shared = UserService()

    private let firestore: FirestoreServiceProtocol
    private let usersCollection = "users"

    /// `nil` means the real Firestore. Only create this after `FirebaseApp.configure()`.
    init(firestore: FirestoreServiceProtocol? = nil) {
        self.firestore = firestore ?? FirebaseFirestoreService()
    }

    // MARK: - User Profile Management

    /// Creates the profile on first sign-in; afterwards only updates the email and `lastLoginAt`.
    /// Merging keeps any fields added to the profile later.
    func createOrUpdateUserProfile(userID: String, email: String?) async throws {
        var fields: [String: Any] = [
            UserProfile.Field.id: userID,
            UserProfile.Field.lastLoginAt: FieldValue.serverTimestamp()
        ]
        if let email {
            fields[UserProfile.Field.email] = email
        }
        try await self.profileDocument(userID).setData(fields, merge: true)
    }

    /// The user's profile, or nil if it doesn't exist yet.
    func fetchUserProfile(userID: String) async throws -> UserProfile? {
        let document = try await self.profileDocument(userID).getDocument()
        guard document.exists, let data = document.data() else {
            return nil
        }
        return UserProfile(id: userID, data: data)
    }

    /// Deletes the profile. Call before deleting the Firebase Auth user, while still signed in.
    func deleteUserDocument(userID: String) async throws {
        try await self.profileDocument(userID).delete()
    }

    private func profileDocument(_ userID: String) -> DocumentReferenceProtocol {
        self.firestore.collection(self.usersCollection).document(userID)
    }
}
