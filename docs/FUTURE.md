# Future Work — Dumps

> Parked items that are intentionally deferred from v0.0.1.
> The current build (signed Developer ID + AppIcon `v0.0.1`) is production-runnable; these are the next unlocks.

## Must Do Next (before App Store / wider launch)

### 1. Notarization + Stapling (unlocks silent Gatekeeper pass)
**Blocked on:** App Store Connect API key (`.p8` + Key ID + Issuer ID) and the Developer ID `.p12` in GitHub Secrets.

**Steps:**
1. Create API key at **App Store Connect → Users and Access → Integrations → Team Keys** (Admin + Download `.p8`).
2. Add repo secrets to `prag-man/dumps` → Settings → Secrets and variables → Actions:
   - `APPLE_CERTIFICATE_P12_B64` — `base64` of exported Developer ID `.p12`
   - `APPLE_CERTIFICATE_PASSWORD` — its password (if any)
   - `APPLE_API_KEY_P8_B64` — `base64` of `AuthKey_XXXXXXXX.p8`
   - `APPLE_API_KEY_ID` — e.g. `ABCDE12345`
   - `APPLE_API_ISSUER_ID` — UUID at top of Team Keys page
3. Tag `v0.0.2` (or re-run `Release` dispatch) — the workflow at `.github/workflows/release.yml` will auto:
   - archive with `Developer ID Application: Pragyam Soni (TSYXZS29G9)` + hardened runtime,
   - `notarytool submit --wait` for both `.zip` and `.dmg`,
   - `stapler staple` + `spctl` verify,
   - publish notarized `Dumps-v0.0.2.dmg/.zip` + correct `SHA256SUMS.txt` to the GitHub Release.

**Local test (before pushing secrets):**
```bash
mkdir -p ~/.appstoreconnect/private_keys
cp AuthKey_XXXXXXXX.p8 ~/.appstoreconnect/private_keys/
xcrun notarytool submit /tmp/Dumps-v0.0.1.dmg \
  --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXX.p8 \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" --wait --timeout 30m
xcrun stapler staple /tmp/Dumps-v0.0.1.dmg && spctl -a -vvv -t install /tmp/Dumps-v0.0.1.dmg
```

Current `v0.0.1` ships as `source=Unnotarized Developer ID` — valid signature, just not stapled yet. Reads as **Rejected by Gatekeeper** under strict `spctl`; notarized builds pass as **Accepted**.

### 2. Configurable Global Shortcut recorder (Settings)
- Today: fixed `⌥ Space`. Need a recorder control (`Preferences` typed model already exists) that re-registers via `HotkeyManager` and persists `keyCode + modifiers`.
- Surface collision error gracefully.

### 3. App/Social Preview media
- `docs/media/hero.png`, `capture.gif` (4–6s ⌥Space loop), `library.png`, `social-preview.png` — per audit README plan. Wire into README once captured on real notch hardware.

### 4. Signed DMG via CI certificate import
- Once `APPLE_CERTIFICATE_P12_B64` is set, `release.yml`'s `Import Developer ID certificate` step will bring the keychain into the runner so the archive step signs there too (local signing already verified). No code change needed — just secrets.

## Nice to Have / Post-v1

- FTS5 (only after profiling LIKE at 5–10k dumps).
- Export (JSON/Markdown).
- Menu-bar icon toggle polish (already toggles via `Preferences.showMenuBarIcon`).
- Dedicated accessibility pass (VoiceOver labels, focus ring audit).
- Branch protection (require CI status on `main`).

## Technical Notes (so future you doesn't re-derive)
- Signing identity: `Developer ID Application: Pragyam Soni (TSYXZS29G9)` (`533B376BB0AFE991…`), Team `TSYXZS29G9`.
- Project: `MARKETING_VERSION=0.0.1`, `CURRENT_PROJECT_VERSION=1`, `CODE_SIGN_STYLE=Manual` on **Release** only, `Automatic` on Debug, hardened runtime enabled.
- Icon: `Dumps/Resources/Assets.xcassets/AppIcon.appiconset` → `Assets.car` → `AppIcon.icns` (custom notch+capsule violet dot).
- DB: SQLite WAL at `~/Library/Application Support/Dumps/dumps.sqlite`; `Migrations.bootstrapIfNeeded` ensures Inbox.
- `v0.0.1` tag at `862c2b2` — re-tagging after secret setup will produce `v0.0.2` as the first notarized release.

---
*Last updated: 2026-08-20 — from `main@862c2b2`, latest Release `v0.0.1`.*
