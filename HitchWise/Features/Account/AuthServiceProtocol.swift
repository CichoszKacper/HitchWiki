//
//  AuthServiceProtocol.swift
//  HitchWise
//
//  Thin wrappers around Firebase Auth and Firestore (same pattern as Fault Navigator),
//  so AuthManager and UserService only talk to protocols and can be tested with fakes.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firebase Auth Protocols

protocol AuthServiceProtocol {
    var currentUser: UserProtocol? { get }
    func signIn(with credential: AuthCredential) async throws -> UserProtocol
    func signOut() throws
    /// Calls `onChange` on the main thread whenever the user signs in or out, for the app's lifetime.
    func listenForChanges(_ onChange: @escaping (UserProtocol?) -> Void)
}

protocol UserProtocol {
    var uid: String { get }
    var email: String? { get }
    /// "google.com"…
    var providerIDs: [String] { get }
    func reauthenticate(with credential: AuthCredential) async throws
    func delete() async throws
}

// MARK: - Firebase Firestore Protocols

protocol FirestoreServiceProtocol {
    func collection(_ collectionPath: String) -> CollectionReferenceProtocol
}

protocol CollectionReferenceProtocol {
    func document(_ documentPath: String) -> DocumentReferenceProtocol
}

protocol DocumentReferenceProtocol {
    func getDocument() async throws -> DocumentSnapshotProtocol
    func setData(_ fields: [String: Any], merge: Bool) async throws
    func delete() async throws
}

protocol DocumentSnapshotProtocol {
    var exists: Bool { get }
    func data() -> [String: Any]?
}

// MARK: - Real Firebase Implementations

final class FirebaseAuthService: AuthServiceProtocol {
    private let auth = Auth.auth()

    var currentUser: UserProtocol? {
        self.auth.currentUser.map(FirebaseUser.init)
    }

    func signIn(with credential: AuthCredential) async throws -> UserProtocol {
        let result = try await self.auth.signIn(with: credential)
        return FirebaseUser(result.user)
    }

    func signOut() throws {
        try self.auth.signOut()
    }

    func listenForChanges(_ onChange: @escaping (UserProtocol?) -> Void) {
        _ = self.auth.addStateDidChangeListener { _, user in
            onChange(user.map(FirebaseUser.init))
        }
    }
}

final class FirebaseUser: UserProtocol {
    private let user: User

    init(_ user: User) {
        self.user = user
    }

    var uid: String {
        self.user.uid
    }

    var email: String? {
        self.user.email
    }

    var providerIDs: [String] {
        self.user.providerData.map(\.providerID)
    }

    func reauthenticate(with credential: AuthCredential) async throws {
        _ = try await self.user.reauthenticate(with: credential)
    }

    func delete() async throws {
        try await self.user.delete()
    }
}

final class FirebaseFirestoreService: FirestoreServiceProtocol {
    private let firestore = Firestore.firestore()

    func collection(_ collectionPath: String) -> CollectionReferenceProtocol {
        FirebaseCollectionReference(reference: self.firestore.collection(collectionPath))
    }
}

struct FirebaseCollectionReference: CollectionReferenceProtocol {
    let reference: CollectionReference

    func document(_ documentPath: String) -> DocumentReferenceProtocol {
        FirebaseDocumentReference(reference: self.reference.document(documentPath))
    }
}

struct FirebaseDocumentReference: DocumentReferenceProtocol {
    let reference: DocumentReference

    func getDocument() async throws -> DocumentSnapshotProtocol {
        FirebaseDocumentSnapshot(snapshot: try await self.reference.getDocument())
    }

    func setData(_ fields: [String: Any], merge: Bool) async throws {
        try await self.reference.setData(fields, merge: merge)
    }

    func delete() async throws {
        try await self.reference.delete()
    }
}

struct FirebaseDocumentSnapshot: DocumentSnapshotProtocol {
    let snapshot: DocumentSnapshot

    var exists: Bool {
        self.snapshot.exists
    }

    func data() -> [String: Any]? {
        self.snapshot.data()
    }
}
