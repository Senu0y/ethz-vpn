<p align="center">
  <img src="icon.icon/Assets/network.badge.shield.half.filled@4x.png" width="128" alt="ETHZ VPN icon">
</p>

# ETHZ VPN

Menu bar app and CLI for connecting to the ETH Zurich VPN using openconnect with TOTP and Keychain integration. Supports multiple named profiles for different realms or accounts.

**Requirements:** macOS 14 or later on Apple Silicon (arm64).

You can build and install the app on your own Mac using your own **Apple Development** certificate. The app, helper, and CLI are signed together with your identity; no certificate from the repository maintainer is needed. Start with [Install with your own Apple certificate](#install-with-your-own-apple-certificate).

---

## What's included

| Component | Description |
|-----------|-------------|
| `ETHZ VPN.app` | Menu bar app — left-click for menu, right-click to toggle VPN |
| `ethz-vpn-legacy.sh` | Legacy CLI using sudo/OpenConnect |
| `ethz-vpn.sh` | New CLI using the signed privileged helper |

The app and both CLIs share the same Keychain entries and profile store, so profiles created in one are available in the others.

---

## Quick start (end user)

1. Follow [Install with your own Apple certificate](#install-with-your-own-apple-certificate) to build, sign, and install the app and protected runtime.
2. Double-click the app
3. The **Manage Profiles** window opens automatically on first launch
4. Click **Add Profile** and fill in:
   - **Name** — a label for this config (e.g. `Student`, `Staff`)
   - **Username** — your ETH username without `@ethz.ch`
   - **WLAN Password** — your ETH network password
   - **OTP Secret** — the base32 TOTP secret from your authenticator setup
   - **Realm** — leave as `student-net` unless you have a different group
5. Click **Save** to store credentials in your Keychain. Separately, click **Enable VPN Access** and approve ETHZ VPN in **System Settings → General → Login Items & Extensions**. macOS controls this authorization prompt. Saving a profile never installs a sudoers rule.
6. Use the menu bar icon to connect and disconnect

Subsequent launches skip the wizard automatically.

---

## Multiple profiles

You can create as many profiles as you like (e.g. one for `student-net`, one for `staff-net`).

**In the menu bar app:**

- Open **Manage Profiles...** to add, edit, duplicate, delete, or set a default profile
- When you have more than one profile, the **Connect** menu expands into a submenu listing all profiles
- The active (last-used) profile is shown with a checkmark
- **Right-click** the menu bar icon to instantly connect (default profile) or disconnect

**In the new CLI:**

```bash
ethz-vpn connect staff
ethz-vpn default student
ethz-vpn profiles
```

---

## Install with your own Apple certificate

### 1. Prepare your Mac and checkout

Install [Xcode](https://developer.apple.com/xcode/) and open it once to finish its setup. You also need [Homebrew](https://brew.sh/), administrator access on this Mac, and your own Apple Account signed in to Xcode.

Clone the repository, or open your existing checkout containing the new helper:

```bash
git clone https://github.com/Senu0y/ethz-vpn.git
cd ethz-vpn
```

Run the remaining terminal commands from the repository root. Install the build dependencies:

```bash
brew install openconnect dylibbundler python
```

Homebrew is used to prepare the bundle. The installed helper runs the bundled OpenConnect and libraries, with no Homebrew fallback.

### 2. Create an Apple Development certificate

If you already have a valid Apple Development identity on this Mac, skip to step 3.

1. Open **Xcode → Settings → Accounts** (called **Apple Accounts** in some versions).
2. Add or select your Apple Account.
3. Select your team. For local personal development, use your **Personal Team** if available.
4. Click **Manage Certificates…**.
5. Click **+ → Apple Development** and wait for Xcode to create the certificate and private key.

See [Apple's certificate-management instructions](https://help.apple.com/xcode/mac/current/en.lproj/dev154b28f09.html).

**Apple Development signing has been verified with this project's installer and authenticated helper communication on a local Mac.** You do not need a Developer ID Application certificate for this local installation flow. Your account must still be able to create a valid development identity; merely seeing a Personal Team in Xcode does not mean a certificate exists yet.

Apple Development is for development and testing. Developer ID Application is the separate path used for notarized distribution to other users. See [Apple's certificate types](https://developer.apple.com/help/account/certificates/certificates-overview/). Other users following this guide should create their own identity and sign their own build.

### 3. Select your actual signing identity

```bash
security find-identity -v -p codesigning
```

Find an entry whose quoted name starts with `Apple Development:`. Copy its **40-character hexadecimal hash**, between the numbered entry and the quoted name. This is a certificate identifier, not your Team ID. The full quoted certificate name also works.

The following commands ask you to paste that hash; they contain no example certificate name to replace:

```bash
printf 'Paste your Apple Development certificate hash, then press Enter: '
read -r SIGN_IDENTITY
```

If the output says **`0 valid identities found`**, stop here and complete step 2. A usable signing identity requires both the certificate and its matching private key on this Mac. If importing an existing identity, a certificate-only `.cer` file may be insufficient; import the matching identity and private key from your own certificate backup.

The helper checks the signing Team ID at runtime. No Team ID or certificate hash needs to be edited into the Swift source. All components must be signed together using the selected identity, which `make install` does automatically.

### 4. Build, sign, and install

If upgrading, first disconnect the VPN. For an existing helper installation, also select **Disable VPN Access** in **Manage Profiles** and quit the app. The installer refuses to replace a running helper.

In the same terminal where you set `SIGN_IDENTITY`, run:

```bash
make fetch-openconnect
make install SIGN_IDENTITY="$SIGN_IDENTITY"
```

The build may show a Keychain prompt asking to let `codesign` use your signing key. Installation then asks for your Mac administrator password through `sudo`. Run `make` as your normal user; only the installation step needs administrator privileges.

The installer creates:

| Location | Purpose |
|----------|---------|
| `/Applications/ETHZ VPN.app` | The menu bar app, native CLI, and registered helper executable |
| `/Library/Application Support/ETHZ VPN/Runtime.app` | Root-owned execution copy used to launch OpenConnect and its scripts |

The protected runtime prevents replacement of privileged code after signature verification. **Dragging only the `.app` into Applications is not sufficient.** Keep both installed locations intact.

### 5. Enable VPN Access

```bash
open "/Applications/ETHZ VPN.app"
```

Open **Manage Profiles**, click **Enable VPN Access**, and approve ETHZ VPN in **System Settings → General → Login Items & Extensions** when requested. On some macOS versions this page is called **Login Items**. Return to the app; it detects approval automatically.

Signing the app and approving the helper are separate steps. The system's **Open Anyway** option does not replace the signatures required by this project's helper.

### 6. Configure a profile

In **Manage Profiles → Add Profile**, enter your ETH username, WLAN password, base32 OTP secret, and realm (normally `student-net`). Give the profile a name, then save it. Existing profiles and Keychain credentials are retained when upgrading. Saving a profile does not require root access.

You can now connect from the menu bar. To use the terminal, add the new CLI as described below.

### 7. Add and verify the new CLI

From the repository root:

```bash
chmod +x ethz-vpn.sh
sudo mkdir -p /usr/local/bin
sudo ln -s "$PWD/ethz-vpn.sh" /usr/local/bin/ethz-vpn
ethz-vpn status
```

The symlink follows this checkout, so keep it in place. If the link already exists, inspect it with `ls -l /usr/local/bin/ethz-vpn`; skip creating it if it already points to this checkout. If your shell cannot find the command, use `./ethz-vpn.sh` from the repository root or add `/usr/local/bin` to your `PATH`.

A response of `disconnected` confirms that the signed CLI reached the helper. It does not test an ETH connection. Disconnect any legacy VPN session, then connect using the default profile:

```bash
ethz-vpn connect
ethz-vpn status
ethz-vpn disconnect
```

To select a particular profile, append its saved name to `ethz-vpn connect`.

### Installation troubleshooting

| Symptom | Next step |
|---------|-----------|
| `0 valid identities found` | Create an Apple Development certificate in Xcode, or import your identity with its private key. Check certificate validity and Keychain availability. |
| `no identity found` during signing | Rerun the identity listing and paste an actual hash. Text such as `Exact Name From Output` is not a certificate name. Set `SIGN_IDENTITY` again if you opened a new terminal. |
| CLI says the new app is missing | Complete `make install`; `make build`, `make bundle`, or copying the old app alone does not install the new runtime and native CLI. |
| Helper unavailable or approval required | Enable VPN Access in the installed app and approve it in System Settings. |
| Signature or Team ID mismatch | Disable the existing helper, quit the app, and rebuild/install all components using the same identity. Do not mix binaries signed by different teams. |
| Installer says the helper is running | Disconnect, disable VPN Access, and quit before retrying installation. |
| Two ETHZ VPN apps appear | An old copy may remain in `~/Applications`. Launch the new one from `/Applications/ETHZ VPN.app`; the installer does not remove the old copy. |

### Diagnostic logs

The app and privileged helper write privacy-safe lifecycle and route-cleanup events to the macOS unified log. There is no ordinary ETHZ VPN `.log` file. macOS manages the underlying log store internally under `/var/db/diagnostics`; use the `log` command or Console.app instead of reading files there directly.

The logs do not contain usernames, realms, passwords, OTP secrets, cookies, raw OpenConnect output, or internal VPN addresses. They contain connection-state changes, helper startup and communication failures, OpenConnect exit statuses, safe network-error categories, physical-network changes, and route-cleanup decisions.

To watch a connection attempt live:

```bash
log stream --style compact --level info \
  --predicate 'subsystem == "com.dcamenisch.ethz-vpn-menubar" OR subsystem == "com.dcamenisch.ethz-vpn-menubar.helper"'
```

To inspect recent events after a failure:

```bash
log show --last 1h --style compact \
  --predicate 'subsystem == "com.dcamenisch.ethz-vpn-menubar" OR subsystem == "com.dcamenisch.ethz-vpn-menubar.helper"'
```

If privileged-helper messages do not appear, stream at debug level with administrator access:

```bash
sudo log stream --style compact --level debug \
  --predicate 'subsystem == "com.dcamenisch.ethz-vpn-menubar" OR subsystem == "com.dcamenisch.ethz-vpn-menubar.helper"'
```

For a graphical view, open `/System/Applications/Utilities/Console.app`, select the Mac under **Devices**, click **Start streaming**, and search for `com.dcamenisch.ethz-vpn-menubar`.

The helper keeps a root-only ownership record for the exact VPN-server host route it creates. If cleanup is interrupted, the next connection removes that recorded route only when its destination, gateway, and interface still match; routes changed or installed by another tool are left untouched.

## Build targets and distribution

For compilation and nonprivileged checks without installation:

```bash
make build
make test
```

An ad-hoc or unsigned build cannot authenticate to this helper. `make bundle` alone is useful for development but does not produce an operational installation.

| Target | Description |
|--------|-------------|
| `make fetch-openconnect` | Bundle OpenConnect, its libraries, and vpnc-script |
| `make build` | Compile the app, privileged helper, and native CLI |
| `make test` | Check credential validation, route identity, and shell syntax |
| `make bundle` | Assemble an unsigned development bundle in `dist/` |
| `make sign SIGN_IDENTITY="…"` | Sign nested binaries and the app with hardened runtime |
| `make install SIGN_IDENTITY="…"` | Install the signed app and protected runtime |
| `make dist SIGN_IDENTITY="…"` | Produce a signed zip; notarization is a separate release step |
| `make uninstall` | Remove installed app/runtime after VPN Access is disabled; retain credentials |

For distribution, use a **Developer ID Application** identity rather than the local Apple Development identity. Notarize the signed zip with `xcrun notarytool submit ... --keychain-profile ... --wait`, staple the accepted ticket to the app using `xcrun stapler staple`, and recreate the zip. Recipients must install both the visible app and protected runtime; dragging the app alone is insufficient. From this repository, the installer is `sudo /bin/sh Support/install.sh "/path/to/ETHZ VPN.app"`.

The release workflow requires signing secrets and notarizes before publishing; it must not publish unsigned VPN helpers.

Configure repository variables `SIGN_IDENTITY` and `APPLE_TEAM_ID`, and secrets `SIGNING_CERTIFICATE_P12` (base64-encoded Developer ID certificate and private key), `SIGNING_CERTIFICATE_PASSWORD`, `SIGNING_KEYCHAIN_PASSWORD`, `NOTARIZATION_APPLE_ID`, and `NOTARIZATION_PASSWORD` (app-specific password) before triggering a release. These are referenced by the workflow; no credentials are stored in the repository.

---

## CLI reference and legacy fallback

The new helper-based command is `ethz-vpn`:

```text
ethz-vpn connect [name]    Connect using a named or default profile
ethz-vpn disconnect        Disconnect the helper's session
ethz-vpn status            Show the helper's connection status
ethz-vpn profiles          List saved profiles
ethz-vpn add               Add a profile interactively
ethz-vpn edit <name>       Edit a profile
ethz-vpn delete <name>     Delete a profile
ethz-vpn default <name>    Set the default profile
ethz-vpn --help            Show help
```

`ethz-vpn-legacy` / `ethz-vpn-legacy.sh` retains the legacy sudo/OpenConnect flow for existing users. Installing or enabling the new helper preserves its sudoers rules. New installations should use `ethz-vpn` and do not need to set up legacy sudoers rules.

To keep the legacy command available, run this from the repository root:

```bash
chmod +x ethz-vpn-legacy.sh
sudo ln -s "$PWD/ethz-vpn-legacy.sh" /usr/local/bin/ethz-vpn-legacy
```

If you previously used `ethz-vpn2`, the new CLI is now named `ethz-vpn`. A link to this checkout's `ethz-vpn.sh` automatically uses the new implementation. Use `ethz-vpn-legacy` for the previous implementation. Remove an obsolete `ethz-vpn2` symlink after checking its target with `ls -l /usr/local/bin/ethz-vpn2`.

`ethz-vpn` reads credentials from your user Keychain and passes them through stdin to the signed native CLI inside `/Applications/ETHZ VPN.app`. It requires installation and approval of the new helper; merely adding the command does not activate the helper. Both commands share profiles and Keychain entries. Disconnect the legacy VPN before connecting through the new helper. Profile management uses `security` and `python3`.


---

## Credentials storage

| Secret | Where |
|--------|-------|
| WLAN password (per profile) | macOS Keychain (`eth-vpn-password-<profile-id>`) |
| OTP secret (per profile) | macOS Keychain (`eth-vpn-token-<profile-id>`) |
| Profile list | `~/.local/share/ethz-vpn-connect/profiles.json` |
| Active profile ID | App `UserDefaults` key `eth-vpn-active-profile-id`; the shell CLI maintains its own default selection |

## Privileged operations

`SMAppService` registers the bundled root daemon. XPC requires Apple-signed app or CLI identities from the helper's own Team ID; clients also verify the helper's signature. Only the current desktop user may control a session, and another user cannot take over an existing session.

The helper exposes connect, disconnect, status, and removal of the two dedicated legacy sudoers files. It accepts no executable paths, arbitrary argument lists, shell commands, or process IDs. It validates profile fields, uses a private root-only session directory for the OTP configuration, and supplies the password on stdin. Keychain access remains in the unprivileged app/CLI. Authentication output is not logged.

Disconnect signals only the helper's own child, escalating from SIGINT to SIGTERM and then SIGKILL if needed. The bundled network script reports tunnel readiness, IP address, and the server host route. After process exit, cleanup removes that route only if its destination, gateway, and interface still match the session record. The menu bar app restarts sessions it started when physical interface addresses or routers change. This does not attempt to adopt older OpenConnect processes or clean routes from unrecorded sessions.

During side-by-side testing, approval preserves `/etc/sudoers.d/ethz-vpn` and `/etc/sudoers.d/eth-vpn` so the legacy CLI stays available. The helper retains an explicit cleanup operation for a later migration; the app does not invoke it automatically. Existing credentials and profile IDs are retained. Disconnect the old VPN before upgrading: the new helper will not kill an unrelated or legacy OpenConnect process.

## Updating

Disconnect the VPN, choose **Disable VPN Access** in **Manage Profiles**, and quit before running `make install` again. The installer refuses to overwrite a running helper. Re-enable VPN Access after updating. Keep the app at its installed location.

---

## Uninstall

Disconnect the VPN, click **Disable VPN Access** in **Manage Profiles**, then quit and run:

```bash
make uninstall
```

Credentials and profiles are retained. Delete profiles in **Manage Profiles** first if you also want to remove their Keychain entries.

## Validation before release

Automated checks cover input injection rejection, conservative route identity comparison, compilation of all targets, shell syntax, and bundled library paths. A signed installation must also be exercised on a Mac: approve/revoke the helper, connect with Keychain credentials, connect/disconnect from the CLI, switch Wi-Fi, disconnect during authentication, reject an unsigned XPC client, and upgrade/uninstall. Compilation alone does not verify macOS approval or an actual ETH VPN connection.
