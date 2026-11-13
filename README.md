# HitchWiki

## Firebase

Firebase project: `hitchwise-app` (see `.firebaserc`). Used for optional sign-in and user profiles only.

- **Auth:** Sign in with Google only for now (no email/password). Sign in with Apple will be added once the app joins the Apple Developer Program (it needs a paid account). Signing in is optional; the guide and map work without it. Sign in, sign out and delete account live in Settings › Account.
- **Firestore:** one profile per user at `users/{uid}` with `id`, `email` and `lastLoginAt` (server time, updated on sign-in and on each launch while signed in). Created on first sign-in. `firestore.rules` lets users read, write and delete only their own profile, with only those fields.

Code: `HitchWise/Features/Account/` (same layering as Fault Navigator: protocol wrappers → `UserService` → `AuthManager`).

### Deploying the rules

```
npm install -g firebase-tools
firebase login
firebase deploy --only firestore
```

### One-time setup

Firebase console (`hitchwise-app`):
1. Authentication › Sign-in method: enable **Google**.
2. Firestore Database: create the database (production mode; `eur3` or `europe-west2`), then deploy the rules above.
3. Project settings › iOS app: make sure the bundle ID is `com.kacpercichosz.hitchwise`, then download `GoogleService-Info.plist` again **after** enabling Google. The new file has `CLIENT_ID` and `REVERSED_CLIENT_ID`, which Google sign-in needs.

Xcode (HitchWise target):
1. Package dependencies: from `firebase-ios-sdk` add **FirebaseAuth** and **FirebaseFirestore**; add `https://github.com/google/GoogleSignIn-iOS` with **GoogleSignIn** and **GoogleSignInSwift**.
2. Info › URL Types: add one with URL Schemes = the `REVERSED_CLIENT_ID` value from `GoogleService-Info.plist`.
3. Make sure `GoogleService-Info.plist` and the `Features/Account` folder are in the HitchWise target.
