# HitchWiki

## Maps

Every map in the app (the Map tab, a page's spots, page headers, the home screen's thumbnails) is MapLibre
(`maplibre-gl-native-distribution`) drawing our own style (`Shared/MapEngine/MapStyle.swift`): motorways, slip roads,
road numbers and petrol stations stand out; shops and other points of interest are left off. Spots are drawn by
`HitchMapView`, which lets MapLibre cluster the ~55,000 points on the GPU.

- **Online:** tiles come from [OpenFreeMap](https://openfreemap.org) (free, no key, commercial use allowed). Their
  terms ask for a unique User-Agent (`HitchWise/<version> (iOS; …)`, set in `MapTileLoader`) and cap offline
  downloads from their servers at 3,000 tiles / 50 MB, which is why country maps come from our own host.
- **Offline:** one MBTiles file per country, cut from OpenFreeMap's weekly planet by `tools/build_map_packs.py`
  (same tiles, so online and offline maps match). The app downloads them from `HWMapPacksBaseURL` (Info.plist) in
  Settings › Offline maps or from the map's download button. While it's empty, that screen says "coming soon".
- All map requests go to a made-up host that `MapTileLoader` answers: from a downloaded country file if one covers
  the tile, otherwise from OpenFreeMap. Label fonts (Noto Sans, OFL) for Latin, Cyrillic, Greek, Arabic, Hebrew,
  Thai and Georgian are bundled in `HitchWise/MapGlyphs`.
- Credit: "© OpenStreetMap contributors" (ODbL) and OpenMapTiles must stay visible on maps (`MapAttribution`).
- Downloads are free for now; `OfflineMapStore.requiresPurchase` is the single place to gate them later.

### Publishing country maps (Cloudflare R2)

1. Create an R2 bucket and give it a custom domain (R2's `r2.dev` address is rate-limited and not for production).
   Storage is about $0.015/GB a month after the free 10 GB; downloads are free.
2. Install the tools and set up rclone with an R2 **Account API token** (Object Read & Write, this bucket only):
   ```
   brew install pmtiles rclone
   python3 -m venv tools/.venv && tools/.venv/bin/pip install shapely pmtiles
   rclone config create r2 s3 provider=Cloudflare access_key_id=… secret_access_key=… endpoint=https://<account id>.r2.cloudflarestorage.com acl=private
   ```
3. Make and upload the countries. Only each country's tiles are downloaded from OpenFreeMap's newest planet (not the
   whole ~90 GB file), each one is uploaded and deleted straight away, and `index.json` goes up last:
   ```
   tools/.venv/bin/python tools/build_map_packs.py maps/ --upload r2:hitchwise-maps/maps --countries LU,SI
   tools/.venv/bin/python tools/build_map_packs.py maps/ --upload r2:hitchwise-maps/maps
   ```
   Each file also gets the country's petrol stations from OpenStreetMap (via the free Overpass service; the
   script waits and retries when it's busy), because the map's tiles only have them at zoom 14. The app draws
   them as their own layer, with motorway services bigger and visible from further out.
   The first line is a quick test with two small countries; the second does every country (it skips those already
   done, so it can be stopped and started again). Sizes at zoom 13: Luxembourg 27 MB, Slovenia 112 MB, Poland
   ~0.75 GB, Germany ~1.2 GB.
4. Check `https://<your public URL>/maps/index.json` opens in a browser.
5. Set `HWMapPacksBaseURL` in `HitchWise/Info.plist` to that folder, e.g. `https://maps.example.com/maps/`.

Re-running with a newer planet changes the version in `index.json`, and the app offers an update for downloaded countries.

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
