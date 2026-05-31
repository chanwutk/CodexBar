---
summary: "Create and automate the chanwutk Homebrew tap for CodexBar fork releases."
read_when:
  - Creating chanwutk/homebrew-codexbar
  - Wiring fork releases to Homebrew cask updates
  - Installing this fork through brew
---

# Homebrew Automation

This fork uses a separate tap repo:

```text
chanwutk/homebrew-codexbar
```

Homebrew maps `brew tap chanwutk/codexbar` to the GitHub repo `chanwutk/homebrew-codexbar`, so the install command becomes:

```sh
brew tap chanwutk/codexbar
brew install --cask chanwutk/codexbar/codexbar
brew upgrade --cask chanwutk/codexbar/codexbar
```

## Recommended Release Flow

Use a tag or manual release workflow, not every push to `main`.

```sh
git fetch upstream
git merge upstream/main
# resolve conflicts, run checks, update CHANGELOG.md and version.env
git push origin main
git tag v0.31.1
git push origin v0.31.1
```

The automation chain (all on free GitHub-hosted runners, no paid Apple account — see
[Zero-Dollar Deployment](#zero-dollar-deployment)) is:

1. You publish a GitHub Release for the tag (no local build needed).
2. `.github/workflows/release-cli.yml` runs on `release.published`.
3. The `build-app` job builds the **ad-hoc signed** universal app and uploads `CodexBar-macos-universal-<version>.zip`.
4. The `build-cli` job builds the CLI tarballs and uploads them to the same GitHub Release.
5. After both finish, it dispatches `chanwutk/homebrew-codexbar` workflow `update-formula.yml`.
6. The tap workflow rewrites `Casks/codexbar.rb` and `Formula/codexbar.rb`, commits, and pushes.
7. Your Mac updates with `brew upgrade --cask chanwutk/codexbar/codexbar`.

Pushing every upstream sync directly to a release is possible, but it is brittle: sync fixes, conflict cleanup, and failed build retries would all publish partial release attempts. Tag-based release keeps those separate.

## Create the Tap Repo

Create the repo once:

```sh
gh auth login
gh repo create chanwutk/homebrew-codexbar \
  --public \
  --description "Homebrew tap for the chanwutk CodexBar fork" \
  --clone

cd homebrew-codexbar
mkdir -p Casks Formula .github/workflows
cat > README.md <<'EOF'
# chanwutk Homebrew Tap

Install:

    brew tap chanwutk/codexbar
    brew install --cask chanwutk/codexbar/codexbar
EOF
```

Commit the empty tap scaffold:

```sh
git add README.md Casks Formula .github
git commit -m "Create CodexBar tap"
git push origin main
```

## Tap Update Workflow

Add this file to the tap repo at `.github/workflows/update-formula.yml`.

It accepts the inputs already sent by this repo's `.github/workflows/release-cli.yml`.

```yaml
name: Update Formula

run-name: Update ${{ inputs.formula }} for ${{ inputs.tag }}${{ inputs.request_id && format(' ({0})', inputs.request_id) || '' }}

on:
  workflow_dispatch:
    inputs:
      formula:
        required: true
        type: string
      tag:
        required: true
        type: string
      repository:
        required: true
        type: string
      artifact_template:
        required: false
        type: string
      target_aliases:
        required: false
        type: string
      cask:
        required: false
        type: string
      cask_artifact:
        required: false
        type: string
      request_id:
        required: false
        type: string

permissions:
  contents: write

jobs:
  update-codexbar:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

      - name: Download release assets and update tap
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ inputs.tag }}
          SOURCE_REPO: ${{ inputs.repository }}
          CASK_ARTIFACT: ${{ inputs.cask_artifact }}
        shell: bash
        run: |
          set -euo pipefail

          version="${TAG#v}"
          tmp="$(mktemp -d)"
          mkdir -p Casks Formula

          app_zip="${CASK_ARTIFACT:-CodexBar-macos-universal-{version}.zip}"
          app_zip="${app_zip//\{version\}/$version}"

          assets=(
            "$app_zip"
            "CodexBarCLI-v${version}-macos-arm64.tar.gz"
            "CodexBarCLI-v${version}-macos-x86_64.tar.gz"
            "CodexBarCLI-v${version}-linux-aarch64.tar.gz"
            "CodexBarCLI-v${version}-linux-x86_64.tar.gz"
          )

          for asset in "${assets[@]}"; do
            gh release download "$TAG" --repo "$SOURCE_REPO" --pattern "$asset" --dir "$tmp"
          done

          sha() {
            shasum -a 256 "$1" | awk '{print $1}'
          }

          app_sha="$(sha "$tmp/$app_zip")"
          mac_arm_sha="$(sha "$tmp/CodexBarCLI-v${version}-macos-arm64.tar.gz")"
          mac_x86_sha="$(sha "$tmp/CodexBarCLI-v${version}-macos-x86_64.tar.gz")"
          linux_arm_sha="$(sha "$tmp/CodexBarCLI-v${version}-linux-aarch64.tar.gz")"
          linux_x86_sha="$(sha "$tmp/CodexBarCLI-v${version}-linux-x86_64.tar.gz")"

          cat > Casks/codexbar.rb <<EOF
          cask "codexbar" do
            version "$version"
            sha256 "$app_sha"

            url "https://github.com/chanwutk/CodexBar/releases/download/v#{version}/CodexBar-macos-universal-#{version}.zip",
                verified: "github.com/chanwutk/CodexBar/"
            name "CodexBar"
            desc "Menu bar usage monitor for AI coding providers"
            homepage "https://github.com/chanwutk/CodexBar"

            depends_on macos: ">= :ventura"

            app "CodexBar.app"
            binary "#{appdir}/CodexBar.app/Contents/Helpers/CodexBarCLI", target: "codexbar"

            # This is an ad-hoc signed community build (not Apple-notarized), so macOS
            # Gatekeeper would otherwise block first launch. Strip the quarantine flag
            # that Homebrew applies to the downloaded app on install.
            postflight do
              system_command "/usr/bin/xattr",
                             args: ["-dr", "com.apple.quarantine", "#{appdir}/CodexBar.app"],
                             sudo: false
            end

            caveats <<~EOS
              CodexBar is distributed as an ad-hoc signed build (no paid Apple Developer ID).
              The install step removes the quarantine flag so it launches normally. If macOS
              still blocks it, right-click the app and choose Open, or run:
                xattr -dr com.apple.quarantine "/Applications/CodexBar.app"
            EOS

            zap trash: [
              "~/Library/Application Scripts/com.chanwutk.codexbar",
              "~/Library/Application Scripts/com.chanwutk.codexbar.widget",
              "~/Library/Application Support/CodexBar",
              "~/Library/Application Support/com.chanwutk.codexbar",
              "~/Library/Caches/CodexBar",
              "~/Library/Caches/com.chanwutk.codexbar",
              "~/Library/Containers/com.chanwutk.codexbar",
              "~/Library/Containers/com.chanwutk.codexbar.widget",
              "~/Library/HTTPStorages/com.chanwutk.codexbar",
              "~/Library/HTTPStorages/com.chanwutk.codexbar.binarycookies",
              "~/Library/Preferences/com.chanwutk.codexbar.plist",
              "~/Library/Saved Application State/com.chanwutk.codexbar.savedState",
              "~/Library/WebKit/com.chanwutk.codexbar",
            ]
          end
          EOF

          cat > Formula/codexbar.rb <<EOF
          class Codexbar < Formula
            desc "Menu bar usage and status CLI"
            homepage "https://github.com/chanwutk/CodexBar"
            version "$version"
            license "MIT"

            on_macos do
              if Hardware::CPU.arm?
                url "https://github.com/chanwutk/CodexBar/releases/download/v#{version}/CodexBarCLI-v#{version}-macos-arm64.tar.gz"
                sha256 "$mac_arm_sha"
              else
                url "https://github.com/chanwutk/CodexBar/releases/download/v#{version}/CodexBarCLI-v#{version}-macos-x86_64.tar.gz"
                sha256 "$mac_x86_sha"
              end
            end

            on_linux do
              if Hardware::CPU.arm?
                url "https://github.com/chanwutk/CodexBar/releases/download/v#{version}/CodexBarCLI-v#{version}-linux-aarch64.tar.gz"
                sha256 "$linux_arm_sha"
              else
                url "https://github.com/chanwutk/CodexBar/releases/download/v#{version}/CodexBarCLI-v#{version}-linux-x86_64.tar.gz"
                sha256 "$linux_x86_sha"
              end
            end

            def install
              libexec.install "CodexBarCLI"
              libexec.install "VERSION"
              bin.write_exec_script libexec/"CodexBarCLI"
              bin.install_symlink "CodexBarCLI" => "codexbar"
            end

            test do
              assert_equal "CodexBar #{version}", shell_output("#{bin}/codexbar --version").strip
            end
          end
          EOF

      - name: Commit and push
        run: |
          git add Casks/codexbar.rb Formula/codexbar.rb
          if git diff --cached --quiet; then
            echo "Tap already up to date"
            exit 0
          fi
          git commit -m "codexbar: update formula and cask for ${{ inputs.tag }}"
          git push
```

Commit this workflow in the tap repo:

```sh
git add .github/workflows/update-formula.yml
git commit -m "Add CodexBar tap updater"
git push origin main
```

## Secrets Wiring

There are two repos and two different token scopes:

```text
chanwutk/CodexBar
  Owns app source, GitHub Releases, app zip, CLI tarballs.
  Needs HOMEBREW_TAP_TOKEN so its release workflow can trigger the tap workflow.

chanwutk/homebrew-codexbar
  Owns Casks/codexbar.rb and Formula/codexbar.rb.
  Does not need HOMEBREW_TAP_TOKEN. Its own GITHUB_TOKEN commits the cask/formula update.
```

### 1) Tap Repo Workflow Permissions

In `chanwutk/homebrew-codexbar`, enable write permissions for the built-in `GITHUB_TOKEN`:

1. Open `https://github.com/chanwutk/homebrew-codexbar/settings/actions`.
2. Scroll to **Workflow permissions**.
3. Select **Read and write permissions**.
4. Save.

The tap workflow declares:

```yaml
permissions:
  contents: write
```

That lets the tap repo's built-in `GITHUB_TOKEN` commit regenerated `Casks/codexbar.rb` and `Formula/codexbar.rb`.

### 2) App Repo Secret: HOMEBREW_TAP_TOKEN

The app repo dispatches the tap workflow from `.github/workflows/release-cli.yml`.

Create a fine-grained GitHub personal access token:

1. Open `https://github.com/settings/personal-access-tokens/new`.
2. Token name: `codexbar-homebrew-tap-dispatch`.
3. Resource owner: `chanwutk`.
4. Repository access: **Only select repositories** → `chanwutk/homebrew-codexbar`.
5. Repository permissions:
   - **Actions:** Read and write
   - **Contents:** Read-only
6. Generate the token and copy it once.

Store it in the app repo:

1. Open `https://github.com/chanwutk/CodexBar/settings/secrets/actions`.
2. Click **New repository secret**.
3. Name:

   ```text
   HOMEBREW_TAP_TOKEN
   ```

4. Value: paste the fine-grained token.
5. Save.

Why this token lives in `chanwutk/CodexBar`: the app repo workflow is the workflow making the cross-repo API call to start `chanwutk/homebrew-codexbar/.github/workflows/update-formula.yml`.

Why it does not need Contents write: it does not commit to the tap directly. It only triggers the tap workflow and watches the run. The tap workflow commits with its own `GITHUB_TOKEN`.

## Zero-Dollar Deployment

This is the default path. It needs **no paid Apple Developer account** and **no signing/notarization
secrets** — only `HOMEBREW_TAP_TOKEN` (set up above). GitHub-hosted macOS runners are free for public repos,
so the entire release is automated in CI at no cost.

### How it works

- `.github/workflows/release-cli.yml` has a `build-app` job that runs on a `macos-15` runner.
- It builds the universal app with `CODEXBAR_SIGNING=adhoc` (see `Scripts/package_app.sh`), which
  **ad-hoc signs** the bundle (`codesign --sign -`) instead of using a Developer ID certificate. No Apple
  credentials are involved.
- It strips extended attributes, zips the app as `CodexBar-macos-universal-<version>.zip`, and uploads it to
  the GitHub Release alongside the CLI tarballs.
- `update-homebrew-tap` then waits for both `build-cli` and `build-app`, and dispatches the tap update.

### Releasing

Once `HOMEBREW_TAP_TOKEN` is set, a release is just a tag plus a published GitHub Release — no local build:

```sh
# after bumping version.env + CHANGELOG.md and pushing main
git tag v0.31.1
git push origin v0.31.1
gh release create v0.31.1 --repo chanwutk/CodexBar --title v0.31.1 --generate-notes
```

Publishing the release fires `release-cli.yml`, which builds and uploads the app + CLI assets and updates the
tap. The `build-app` job fails fast if the tag version does not match `version.env`, so bump `version.env`
before tagging.

### Gatekeeper and updates

Ad-hoc signed apps are **not notarized**, so macOS would normally block first launch. Two things handle this:

- The cask's `postflight` removes the `com.apple.quarantine` flag on install (see the cask template above), so
  `brew install --cask` launches cleanly. The `caveats` block documents the manual `xattr` / right-click-Open
  fallback in case a user downloads the zip directly instead of via Homebrew.
- **Sparkle auto-update is disabled** in ad-hoc builds (`package_app.sh` clears `SUFeedURL` when
  `CODEXBAR_SIGNING=adhoc`). Updates come through `brew upgrade --cask chanwutk/codexbar/codexbar` instead,
  which the cask refreshes on every release. This avoids shipping an EdDSA-signed appcast you would otherwise
  have to maintain.

### macOS Ventura (13) compatibility

The minimum supported OS is **Ventura (13)**, which is also the cask floor (`depends_on macos: ">= :ventura"`).

- The app and CLI are built against deployment target macOS 13 (`Package.swift` pins `.macOS(.v13)`,
  `LSMinimumSystemVersion` is `13.0`), so they run on Ventura even though CI builds on a newer
  `macos-15` runner — a newer SDK targeting an older deployment target is supported.
- The `Verify Ventura (macOS 13) compatibility` step in `build-app` runs `otool` against both arch slices of
  the app and CLI binaries and fails the release if either's minimum macOS is above 13. This guards against a
  future dependency silently raising the floor.
- The Notification Center **widget** targets macOS 14.0 (it uses AppIntents-based WidgetKit:
  `AppIntentConfiguration`, `AppIntentTimelineProvider`, `.containerBackground(for: .widget)`), so it cannot
  drop to 13 without a rewrite. On Ventura the app launches and works normally; macOS simply does not load the
  widget. The widget is intentionally excluded from the verification step.

That is the complete $0 deployment. Everything below is optional and only needed if you later want
Apple-notarized, Gatekeeper-clean releases.

## Optional: Signed & Notarized Releases (paid Apple Developer ID)

A notarized release launches with zero Gatekeeper friction and does not depend on the cask stripping
quarantine. It requires a paid Apple Developer Program membership ($99/yr) and a different build path
(`Scripts/sign-and-notarize.sh` / `Scripts/release.sh`) plus these secrets in `chanwutk/CodexBar` (not the tap
repo):

```text
DEVELOPER_ID_CERTIFICATE_P12_BASE64
DEVELOPER_ID_CERTIFICATE_PASSWORD
APP_STORE_CONNECT_API_KEY_P8
APP_STORE_CONNECT_KEY_ID
APP_STORE_CONNECT_ISSUER_ID
SPARKLE_PRIVATE_KEY
HOMEBREW_TAP_TOKEN
```

What each one is for:

- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`: base64-encoded exported Developer ID Application certificate.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: password used when exporting that `.p12`.
- `APP_STORE_CONNECT_API_KEY_P8`: App Store Connect API private key text for notarization.
- `APP_STORE_CONNECT_KEY_ID`: key ID for that App Store Connect API key.
- `APP_STORE_CONNECT_ISSUER_ID`: issuer ID for that App Store Connect API key.
- `SPARKLE_PRIVATE_KEY`: private EdDSA key used to sign Sparkle appcast entries (notarized builds keep
  `SUFeedURL`, so they can auto-update via Sparkle instead of relying only on `brew upgrade`).
- `HOMEBREW_TAP_TOKEN`: the tap dispatch token described above.

All of these (except `HOMEBREW_TAP_TOKEN`) require a paid Apple Developer Program membership. If you go this
route, also remove the cask's `postflight`/`caveats` quarantine workaround, since a notarized app no longer
needs it.

### Acquire the Developer ID certificate

Feeds `codesign` in `Scripts/sign-and-notarize.sh`.

1. In Xcode: **Settings → Accounts**, sign in, select your team → **Manage Certificates → + → Developer ID Application**. (Or create it at `https://developer.apple.com/account/resources/certificates` as "Developer ID Application".)
2. Open **Keychain Access → login → My Certificates** and find `Developer ID Application: <Your Name> (TEAMID)`.
3. Right-click → **Export** → save as a `.p12`. The password you set during export becomes `DEVELOPER_ID_CERTIFICATE_PASSWORD`.
4. Base64-encode the export for the GitHub secret:

   ```sh
   base64 -i DeveloperID.p12 | pbcopy   # paste into DEVELOPER_ID_CERTIFICATE_P12_BASE64
   ```

Then set `MAC_RELEASE_APP_IDENTITY` and `MAC_RELEASE_TEAM_ID` in `.mac-release.env` to your own name/team. The placeholders are already present (commented out); otherwise `Scripts/sign-and-notarize.sh` falls back to the upstream `Developer ID Application: Peter Steinberger (Y5PE65HELJ)` identity, which you cannot sign with.

### Acquire the App Store Connect API key (notarization)

Feeds `xcrun notarytool submit --key/--key-id/--issuer`.

1. Go to `https://appstoreconnect.apple.com/access/integrations/api` (Users and Access → Integrations → App Store Connect API). Requires an Account Holder/Admin role.
2. Click **+** to generate a key, name it, and give it the **Developer** access role (sufficient for notarization).
3. From the keys list, copy:
   - **Key ID** → `APP_STORE_CONNECT_KEY_ID`
   - **Issuer ID** (shown at the top of the section) → `APP_STORE_CONNECT_ISSUER_ID`
4. **Download the `.p8` file — it is only downloadable once.** Its full text (`-----BEGIN PRIVATE KEY-----...`) is `APP_STORE_CONNECT_API_KEY_P8`. The script runs `sed 's/\\n/\n/g'` on it, so either literal `\n` separators or a real multiline value work.

### Acquire the Sparkle EdDSA key

Signs appcast entries for auto-update.

```sh
# generate_keys ships in the Sparkle artifact bundle
./generate_keys                              # stores the key in the login Keychain, prints the public key
./generate_keys -x sparkle_private_key.txt   # also exports the private key to a file
```

- The printed **public key** is the `SUPublicEDKey` in the app's Info.plist, mirrored as `MAC_RELEASE_SUPUBLIC_ED_KEY` in `.mac-release.env`.
- The **private key** (base64 in the exported file, or the Keychain entry) is `SPARKLE_PRIVATE_KEY`.

> [!WARNING]
> `MAC_RELEASE_SUPUBLIC_ED_KEY` and the key-file path in `.mac-release.env` currently point at the inherited upstream `AGCY8w5v...` Sparkle key (the comment marks it "OBSOLETE"). For your fork to ship updates that verify against a key you control, generate your own keypair, put the new public key in `SUPublicEDKey` / `MAC_RELEASE_SUPUBLIC_ED_KEY`, and use the matching private key as `SPARKLE_PRIVATE_KEY`. Otherwise clients cannot validate the updates you sign.

### Current wiring status

The repo fully automates app + CLI builds and the tap update from a published GitHub Release using the
zero-dollar (ad-hoc signed) path. The only GitHub secret required is `HOMEBREW_TAP_TOKEN`.

The signed/notarized path is **not** wired into CI. To produce a notarized release today, run
`./Scripts/release.sh` from a build machine with Xcode/Swift 6.2+ and the signing secrets available locally
(in `.mac-release.env`, the Keychain, or env vars). Those values only need to become GitHub secrets if you
later add a notarized-release CI job.

## Verify

After the first release and tap update:

```sh
brew untap chanwutk/codexbar || true
brew tap chanwutk/codexbar
brew install --cask chanwutk/codexbar/codexbar
brew info --cask chanwutk/codexbar/codexbar
codexbar --version
```

For future releases:

```sh
brew update
brew upgrade --cask chanwutk/codexbar/codexbar
```
