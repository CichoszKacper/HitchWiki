//
//  AccountSection.swift
//  HitchWise
//
//  The Account section at the top of Settings. Signed out: Sign in with Google.
//  Signed in: the email, Sign out and Delete account.
//

import GoogleSignInSwift
import SwiftUI

struct AccountSection: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmsDeletion = false

    var body: some View {
        Section {
            if let account = self.auth.account {
                self.signedIn(account)
            } else {
                self.signInButton
            }
        } header: {
            Text("Account")
        } footer: {
            if self.auth.account == nil {
                Text("Optional. Sign in with Google to create your HitchWise account.")
            }
        }
        .disabled(self.auth.isWorking)
        .confirmationDialog("Delete your account?", isPresented: self.$confirmsDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await self.auth.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your HitchWise account and its data will be deleted. This can't be undone. You'll be asked to confirm with Google once more.")
        }
        .alert("Something went wrong", isPresented: self.showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.auth.errorMessage ?? "")
        }
    }

    // MARK: - Signed in

    @ViewBuilder
    private func signedIn(_ account: AuthManager.Account) -> some View {
        LabeledContent {
            if self.auth.isWorking {
                ProgressView()
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email ?? String(localized: "Signed in", comment: "Account row when the email is unknown"))
                        .foregroundStyle(.primary)
                    Text("Signed in with Google")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "person.crop.circle.fill")
            }
        }

        Button {
            self.auth.signOut()
        } label: {
            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
        }

        Button(role: .destructive) {
            self.confirmsDeletion = true
        } label: {
            Label("Delete account", systemImage: "trash")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Signed out

    private var signInButton: some View {
        VStack(spacing: 10) {
            GoogleSignInButton(scheme: self.colorScheme == .dark ? .dark : .light, style: .wide) {
                Task { await self.auth.signInWithGoogle() }
            }

            if self.auth.isWorking {
                ProgressView()
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var showsError: Binding<Bool> {
        Binding(get: { self.auth.errorMessage != nil }, set: { if !$0 { self.auth.errorMessage = nil } })
    }
}

#Preview {
    List {
        AccountSection()
    }
    .environment(AuthManager.forPreviews())
}
