//
//  UserProfile.swift
//  HitchWise
//
//  The user's profile document in Firestore: users/{uid}.
//  Keep the field list in sync with firestore.rules, which only allows these fields.
//

import Foundation
import FirebaseFirestore

struct UserProfile: Equatable, Identifiable {
    enum Field {
        static let id = "id"
        static let email = "email"
        static let lastLoginAt = "lastLoginAt"
    }

    /// The Firebase Auth uid, also the document ID.
    let id: String
    /// From the sign-in provider (Google for now). May be missing.
    let email: String?
    /// Last sign-in or app launch while signed in. Set by the server.
    let lastLoginAt: Date?

    init(id: String, email: String?, lastLoginAt: Date?) {
        self.id = id
        self.email = email
        self.lastLoginAt = lastLoginAt
    }

    /// Reads a profile from raw Firestore data; unknown or missing fields are tolerated.
    init(id: String, data: [String: Any]) {
        self.id = id
        self.email = data[Field.email] as? String
        self.lastLoginAt = (data[Field.lastLoginAt] as? Timestamp)?.dateValue()
    }
}
