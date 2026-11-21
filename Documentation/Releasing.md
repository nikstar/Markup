# Publishing a macOS release

The release script uses the individual Apple Developer team for Nikita Starshinov (`6RX8GEVB43`) and publishes to `nikstar/Markup`. It uses the account signed into Xcode for Developer ID signing and notarization. The signing keys stay with Apple or in the maintainer’s Keychain.

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. Regenerate the project with `xcodegen generate`. Commit the project and release notes, run the tests, and push the release commit to `main`.
2. Run `Scripts/release.sh` on an Apple silicon Mac with the macOS 27 SDK, an active Apple Developer Program membership, and current agreements. The script archives the committed source, submits it to Apple, and exports the notarized app. If Apple is still processing, run the same command again at the same commit. An accepted submission is reused.
3. Run `Scripts/release.sh --publish Documentation/Releases/1.0.md`, substituting the notes for that version. Authenticate the GitHub CLI as a maintainer first. The script checks the app and extension signatures, validates the stapled ticket, and asks Gatekeeper to assess the app extracted from the ZIP. It publishes the ZIP and its SHA-256 checksum with a tag pointing at the source commit.

The archive, submission marker, and finished download are in `build/releases/<git-commit>/`. Keep this directory when retrying. To verify a download, put the ZIP and checksum in the same directory and run `shasum -a 256 -c Markup-1.0-macOS.zip.sha256`.

Apple documents the distribution requirements in its [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
