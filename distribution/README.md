# Direct distribution and updates

Current scope: Android/Android TV/Fire TV APK, Windows x64 installer, Ubuntu 24.04+ amd64 `.deb`. No store accounts are required for these paths. iOS/tvOS/store publishing is deferred. Other Linux distributions and ARM Linux packages are not covered by the `.deb` recipe.

## Status and release gate

Release tooling is implemented, not yet a published or native-validated release. This workspace currently has no Git remote, Android SDK, Windows C++ toolchain, or Linux build environment. The GitHub workflow has not been executed. Do not call a candidate supported until it passes the device checklist below.

- `release-candidate.yml` builds all candidates, then publishes to `Afbomann/iptv-player` GitHub Releases when **publish** is enabled (default). Disable it for build-only validation. Publication requires every build/test job to succeed and signed Android packaging enabled. No app stores or web deployments are involved.
- Android release tasks require an explicit keystore; debug signing is no longer silently used for release builds.
- Windows packaging uses Inno Setup 6, installs per user, and keeps app data outside the installation directory. Authenticode signing is not configured: unsigned installers can trigger SmartScreen warnings. A publisher certificate should be added before public distribution.
- Linux packaging wraps the full Flutter bundle in a `.deb` with runtime dependencies and a launcher. It does not overwrite profile data.
- The in-app updater checks at startup and every six hours while running. It does not silently replace a running app or bypass OS approval. There is no server running and no live feed until hosting is configured.

## Build candidates with GitHub Actions

1. Put this repository in a GitHub repository you control.
2. Configure these repository secrets (never commit their values):
   - `ANDROID_KEYSTORE_BASE64`: base64 of your release `.jks` file.
   - `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
   - `LUMEN_RELEASE_PRIVATE_KEY`: Ed25519 private key in PKCS#8 PEM form for update metadata.
3. Configure repository variables for update-enabled builds:
   - The workflow embeds `https://github.com/Afbomann/iptv-player/releases/latest/download/updates.json` as the update feed.
   - `LUMEN_UPDATE_PUBLIC_KEY`: base64 of the raw 32-byte Ed25519 public key (not PEM/DER).
4. Run **Build and publish GitHub release** with a semantic version and increasing positive build number. Keep these identical for every platform. Every new release must have a larger build number, including rollback releases. Use a new version each time; existing releases are not overwritten.
5. Download the APK, `.exe`, `.deb` and web artifacts. Windows workers need Inno Setup 6; Linux workers install native build dependencies. The workflow fails if requested signing credentials or build tools are missing.

Back up the Android keystore securely. Future APKs must retain the package ID and signing key to upgrade existing installations. Changing keys ordinarily requires uninstalling first, potentially losing local data.

The publish job checks signing-key consistency and the previous published build, creates `vVERSION` as a draft, uploads all three installers plus `updates.json` and `SHA256SUMS`, then publishes it as latest. A failed upload leaves a draft instead of a partial latest release. Investigate/delete that draft manually before retrying; the workflow never deletes releases automatically. The repository/release assets must be publicly downloadable for unauthenticated app updates; no GitHub token is embedded in the application. Private-repository distribution needs a separate public download host or a different authenticated-update design.

## Local builds

Use Flutter 3.47.4 and the lockfile. Supply the same values through `--build-name`, `--build-number`, `--dart-define=LUMEN_VERSION`, and `--dart-define=LUMEN_BUILD_NUMBER`. Supply the two update variables above with `--dart-define` when enabling update checks.

- Android: install JDK 17 and Android SDK, review/accept SDK licenses yourself, set `LUMEN_ANDROID_KEYSTORE` to an absolute path plus `LUMEN_ANDROID_STORE_PASSWORD`, `LUMEN_ANDROID_KEY_ALIAS`, `LUMEN_ANDROID_KEY_PASSWORD`; run `flutter build apk --release` with the version/define arguments. The universal APK covers the Flutter-supported Android ABIs.
- Windows: install Visual Studio C++ desktop tools and Inno Setup 6; run `flutter build windows --release` with the same arguments. Run ISCC with `/DAppVersion=VERSION`, `/DBuildRoot=ABSOLUTE_RELEASE_BUNDLE`, `/DOutputRoot=ABSOLUTE_OUTPUT_DIRECTORY`, and `distribution/windows/lumen.iss`.
- Linux: build on Ubuntu 24.04 x64 with clang, cmake, ninja, pkg-config, GTK3, libmpv and libsecret development packages. Run `flutter build linux --release`, then `node tooling/package-linux.mjs VERSION BUILD`. Install with `sudo apt install ./distribution/out/lumen-linux-amd64.deb`. In-app installation opens the registered graphical `.deb` handler; a desktop without one requires this package-manager command.

## Sign and publish an update

The Ed25519 release key is separate from the Android keystore and Windows Authenticode certificate. Generate and store it securely outside the repository; `.pem`, `.p12`, `.pfx` and keystore files are ignored. Keep offline recovery copies. Never paste private keys into chat or logs.

1. Test and, where applicable, platform-sign the final packages **before** calculating their hashes.
2. Copy `release.example.json` to a working config, set version/build/notes and the immutable HTTPS release directory. Remove any platform that did not pass validation. Put the named packages together in an artifact directory.
3. Provide the PKCS#8 PEM private key through the secret environment variable `LUMEN_RELEASE_PRIVATE_KEY`.
4. Run `node tooling/release-manifest.mjs CONFIG ARTIFACT_DIRECTORY NEW_OUTPUT_JSON`. It streams SHA-256 hashes, signs exact manifest bytes using Ed25519, and refuses to overwrite an existing output file. It never prints the private key.
5. Upload the packages to immutable versioned URLs. Verify their downloadable hashes. Then atomically replace the JSON at `LUMEN_UPDATE_URL` with the new envelope. Keep old packages available; never overwrite assets at an existing version URL.

Downloads reject unsupported package types, HTTPS downgrade redirects, oversize responses and checksum failures. Incomplete files are deleted; only a verified file is promoted to an installable extension. The Install action rechecks its hash and restricts it to Lumen's update directory. Android uses a narrowly scoped FileProvider and checks the APK package identity; the OS also enforces package signatures. Stop recordings/playback before installing.

For initial installation, users still need a trusted way to obtain the APK/installer/package. A signed update manifest is not a substitute for platform code signing or verifying the initial download.

## Required device acceptance checks

For each advertised platform: clean install; existing-profile upgrade without data loss; wrong-key/tampered update rejection; cancelled download and cancelled installation; unavailable/offline feed; launch/play/pause/seek; audio/subtitles; multiview; app suspension/resumption; LAN QR entry; backup/restore. Android TV and Fire TV additionally require remote navigation and installer-permission tests. Test Windows on a machine without developer tools to identify any missing VC runtime DLLs. Test Linux on a clean Ubuntu 24.04 desktop with dependencies installed through apt.

No APK, Windows installer or Linux package has yet been produced/installed in this workspace. Publishing, credentials and the native build environment remain external prerequisites.
