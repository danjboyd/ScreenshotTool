# Private hosted Sparkle key-match proposal

This local proposal checks whether the existing GitHub Actions `SPARKLE_ED_PRIVATE_KEY`
can sign deterministic dummy bytes that verify against the exact `SUPublicEDKey` in
`Resources/Info-cocoa.plist` from source `01c1ad58677b46774e7bc56ea5f908aaffb637df`.
It uses the pinned Sparkle 2.10.0 `sign_update` and checks that tool's SHA-256 before
the secret is injected. The output is only a pass/fail and SHA-256 of the public dummy
payload. The signature and any signer diagnostics stay in a temporary job directory
that is deleted even on failure.

The manual job runs only for `danjboyd/ScreenshotTool` on `main`, with read-only
repository permissions and a GitHub-hosted macOS runner. It does not need the private
DMG, a self-hosted runner, a keychain account, an artifact upload or a feed URL.
It requires a separately approved workflow commit and dispatch, an available macOS
runner, access to the pinned Sparkle download, and the existing Actions secret.

A pass would establish only that the Actions secret, pinned signer and bundled public
key agree for the dummy payload. It would not establish the exact 0.4.0 DMG signature,
appcast version/length/hash, packaging integrity, install behavior or live update.
The separate same-host exact-DMG proposal is the higher-assurance path for those checks.

If the job fails, stop at the reported gate. Keep signing diagnostics private, delete
the job's temporary directory, and do not publish or reuse the dummy signature.
