---
summary: "Install and update the chanwutk CodexBar fork."
read_when:
  - Installing this fork on a personal Mac
  - Choosing Sparkle or Homebrew updates for fork releases
---

# Installing the Fork

This fork publishes from `chanwutk/CodexBar` and targets macOS 13+.

## Recommended: GitHub Release + Sparkle
1. Publish a signed and notarized release from this repo.
2. Download `CodexBar-macos-universal-<version>.zip` from `https://github.com/chanwutk/CodexBar/releases`.
3. Move `CodexBar.app` to `/Applications`.

This path uses the app's bundled Sparkle feed:

```text
https://raw.githubusercontent.com/chanwutk/CodexBar/main/appcast.xml
```

After each upstream sync, cut a new release from this fork and Sparkle can update the installed app.

## Optional: Homebrew Tap
Use Homebrew if you prefer `brew upgrade` over Sparkle:

```sh
brew tap chanwutk/codexbar
brew install --cask chanwutk/codexbar/codexbar
brew upgrade --cask chanwutk/codexbar/codexbar
```

The tap is expected at `chanwutk/homebrew-codexbar`. Its cask should point at this repo's GitHub release zip and use:

```ruby
depends_on macos: ">= :ventura"
```

Homebrew-installed builds disable Sparkle and show the `brew upgrade` command in About.

See `docs/HOMEBREW_AUTOMATION.md` for creating `chanwutk/homebrew-codexbar` and wiring release automation.

## Release Notes
- `.mac-release.env` points releases and appcast downloads at `chanwutk/CodexBar`.
- Set `MAC_RELEASE_TEAM_ID` and `MAC_RELEASE_APP_IDENTITY` in `.mac-release.env` before signed/notarized fork
  releases.
- `.github/workflows/release-cli.yml` dispatches tap updates to `chanwutk/homebrew-codexbar`.
- If using Sparkle updates, generate and keep a fork-specific EdDSA key pair, set `MAC_RELEASE_SUPUBLIC_ED_KEY`, and pass the private key via `SPARKLE_PRIVATE_KEY_FILE`.
