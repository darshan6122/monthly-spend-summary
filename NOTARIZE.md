# Code signing and notarization (for distribution)

To distribute the app so macOS doesn't show "unidentified developer" or block it on other Macs, you can **sign** and **notarize** the app and DMG with an Apple Developer account.

## Prerequisites

- **Apple Developer Program** membership ($99/year)
- **Developer ID Application** certificate (create in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list))
- **App-specific password** or **App Store Connect API key** for notarization

## 1. Sign the app

In Xcode:

1. Select the **ExpenseReports** target → **Signing & Capabilities**.
2. Set **Team** to your Developer ID team.
3. For **Release**, choose **Sign to Run Locally** or **Developer ID Application** (for distribution outside the App Store).

Or from the command line (after building):

```bash
codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" \
  build/Build/Products/Release/ExpenseReports.app
```

## 2. Notarize the app (or DMG)

Notarization tells Apple’s servers to mark your app as safe so Gatekeeper allows it.

### Option A: Notarize the .app

```bash
# Create a zip of the app (required for notarization)
ditto -c -k --keepParent build/Build/Products/Release/ExpenseReports.app ExpenseReports.zip

# Submit for notarization (use your Apple ID and app-specific password or key)
xcrun notarytool submit ExpenseReports.zip \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password" \
  --wait

# Staple the ticket to the app (after success)
xcrun stapler staple build/Build/Products/Release/ExpenseReports.app
```

### Option B: Notarize the DMG (recommended for installers)

After creating the DMG with `./create-dmg.sh`, sign and notarize the DMG:

```bash
# Sign the DMG
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" ExpenseReports-1.0.dmg

# Submit for notarization
xcrun notarytool submit ExpenseReports-1.0.dmg \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password" \
  --wait

# Staple the notarization ticket to the DMG
xcrun stapler staple ExpenseReports-1.0.dmg
```

## 3. App-specific password

1. Go to [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → **App-Specific Passwords**.
2. Generate a new password and use it as `--password` in the commands above (or store in keychain and use `--keychain-profile`).

## 4. After notarization

- Users can open the app or DMG without right-click → Open.
- Gatekeeper will accept it as notarized by Apple.

For full details see [Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution).
