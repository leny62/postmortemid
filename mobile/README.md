# PostMortemID mobile prototype

Offline Flutter app for muzzle capture, quality checks, enrolment and verification. See the [main README](../README.md) for setup and [docs/architecture.md](../docs/architecture.md) for the design.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Release builds

Pushing a tag such as `v0.2.0` builds a signed arm64 APK and attaches it to a GitHub release (`.github/workflows/release-apk.yml`). Every release must be signed with the same key, or phones cannot update in place.

One-time key setup (keep `release.jks` and its password safe; losing them means users must uninstall and reinstall):

```bash
keytool -genkeypair -keystore release.jks -alias postmortemid -keyalg RSA -keysize 2048 -validity 10000
base64 -i release.jks | pbcopy   # paste into the ANDROID_KEYSTORE_BASE64 secret
```

Add the password as `ANDROID_KEYSTORE_PASSWORD` (Settings > Secrets and variables > Actions), then release with `git tag v0.2.0 && git push origin v0.2.0`. To sign a local release build the same way, put the key in `android/release.jks` and write `android/key.properties` (both git-ignored); without them the release build uses the debug key.
