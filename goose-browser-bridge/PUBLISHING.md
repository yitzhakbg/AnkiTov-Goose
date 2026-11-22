# Publishing Goose Bridge to the Chrome Web Store

This document explains (a) how to package and publish the extension to the Chrome Web Store, (b) how the extension ID / "password" (shared secret) model changes once you publish, and (c) the security trade-offs of each option.

---

## 1. Why the "password" model changes when you publish

**Unpacked (current setup):** Chrome derives the extension ID from an SHA-256 hash of the absolute path (`~/.local/share/goose-browser-ext`), so the ID is stable on your machine but meaningless elsewhere. The `--allowed-origin chrome-extension://<id>` allowlist in the LaunchAgent is therefore machine-specific.

**Published (Chrome Web Store):** Chrome derives the extension ID from the **public key** you ship inside the CRX. This means:
- The ID is the **same on every machine** that installs the published extension.
- You can hard-code `--allowed-origin chrome-extension://<published-id>` once and it works for everyone.
- The "password" (`GOOSE_SERVER__SECRET_KEY`) is still **generated locally per machine** — it is NOT baked into the extension. Each user runs `openssl rand -hex 32` on their own machine, puts it in their own LaunchAgent, and pastes the same value into the Side Panel's Connection settings. The extension is just a dumb WebSocket client; it never needs to know a global secret.

**Key point:** There is no "password generated from the Web Store." The Web Store gives you a **stable extension ID** (via a public key you control). The secret stays local to each user's machine.

---

## 2. Packaging the extension

### 2.1 Generate a keypair (one-time, keep the private key safe)

```bash
# Generate a private key (KEEP THIS SECRET — it IS your extension identity)
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -outform PEM -out goose-bridge-private.pem

# Derive the public key in the format Chrome expects (base64 DER of the RSA public key)
openssl rsa -in goose-bridge-private.pem -pubout -outform DER | openssl base64 -A > goose-bridge-public.key

# Compute the extension ID (SHA-256 of the DER public key, first 16 bytes hex-mapped to a-p)
EXT_ID=$(openssl rsa -in goose-bridge-private.pem -pubout -outform DER | \
  shasum -a 256 | cut -c1-32 | tr '0-9a-f' 'a-p')
echo "Extension ID: $EXT_ID"
```

> ⚠️ **Never commit `goose-bridge-private.pem`.** Store it in your password manager / a secure offline location. If you lose it, you lose the extension ID and must publish a new listing.

### 2.2 Add the public key to `manifest.json`

```json
{
  "manifest_version": 3,
  "name": "Goose Bridge",
  "version": "0.2.0",
  "key": "<paste contents of goose-bridge-public.key>",
  ...
}
```

### 2.3 Zip the extension

```bash
cd extension/
zip -r ../goose-bridge-v0.2.0.zip . -x '*.DS_Store' -x '__MACOSX*'
cd ..
```

---

## 3. Publishing to the Chrome Web Store

1. **Register a Chrome Web Store developer account** at https://chrome.google.com/webstore/devconsole — one-time $5 USD fee (credit card).
2. **Upload the ZIP** via **New item** → drag `goose-bridge-v0.2.0.zip`.
3. **Fill in the listing:**
   - **Category:** Developer Tools (or Productivity).
   - **Language:** English (add more later).
   - **Store listing:** description, 128×128 icon, at least one 1280×800 or 640×400 screenshot.
   - **Privacy tab:**
     - **Single purpose:** "Attach a browser Side Panel to a local Goose ACP server."
     - **Permission justifications:**
       - `sidePanel` — "Required to display the Goose chat sidebar."
       - `tabs` — "Read the active tab's title and URL so the user can send page context to Goose."
       - `contextMenus` — "Add a right-click 'Send selection / page to Goose' item."
       - `storage` — "Persist the local WebSocket URL, secret, and default cwd between sessions."
     - **Does your item use remote code?** **No** (all JS is bundled locally).
     - **Data usage:** Declare you do **not** collect/sell any user data. The extension only talks to `ws://127.0.0.1:3285` on the user's own machine.
4. **Submit for review.** MV3 extensions with only `sidePanel`/`tabs`/`contextMenus`/`storage` (no `<all_urls>` host permissions, no remote code) typically review in **1–3 business days**.
5. **After approval:** the extension is live at `https://chromewebstore.google.com/detail/<EXT_ID>`. Users install it with one click; the ID matches the one you computed in §2.1.

### Updating later

Bump `version` in `manifest.json`, re-zip, and upload the new ZIP on the item's **Package** tab. Review is usually faster for updates.

---

## 4. How the "password" (secret) works after publishing

| Concern | Unpacked (today) | Published (Web Store) |
|---|---|---|
| Extension ID | Derived from local path (machine-specific) | Derived from your public key (same everywhere) |
| `--allowed-origin` | Per-machine, set via `goose-browser-bridge set-origin <id>` | Hard-code once in the LaunchAgent template |
| Secret (`GOOSE_SERVER__SECRET_KEY`) | Generated locally per machine (`openssl rand -hex 32`) | **Same model** — generated locally per machine |
| Where the secret lives | `~/.local/share/goose-browser-ext/.secret` + LaunchAgent plist | Same |
| Who knows the secret | Only the local user | Only the local user |

**The user flow after publishing:**

1. Install from the Web Store (ID is fixed and known).
2. Run the bundled `install.sh` (or follow README) which:
   - Generates a fresh `openssl rand -hex 32` secret.
   - Writes it to `~/.local/share/goose-browser-ext/.secret` (0600).
   - Renders the LaunchAgent plist with that secret + the **hard-coded published extension ID**.
   - Loads the LaunchAgent.
3. User pastes the secret into the Side Panel's Connection settings (or the installer prints it and the user copies it).

**Optional UX improvement (not implemented):** serve the secret over a tiny local HTTP endpoint (`http://127.0.0.1:3285/secret`) that only accepts requests from the extension's origin, so the user never copies/pastes. This trades convenience for a slightly larger attack surface (any local process could hit the endpoint unless you also require a one-time pairing code). Not recommended for v1.

---

## 5. Alternative: self-distribute the CRX without the Web Store

If you don't want the $5 fee or the review process:

- **Enterprise / managed policy install:** Distribute a `.crx` and force-install it via macOS `ExtensionInstallForcelist` policy (requires MDM or a managed profile). Works for your own machines without the Web Store.
- **"Load unpacked" forever:** Keep the current setup. Users must keep Developer mode on; Chrome shows a nag banner on every launch. Fine for personal use, not for distribution.

For a public audience, the Web Store is the only practical route (Chrome/Brave/Helium all support it; Firefox would need a separate WebExtensions port + AMO listing).

---

## 6. Checklist before you hit "Submit"

- [ ] `manifest.json` has `"key"` (public key) and a bumped `version`.
- [ ] `goose-bridge-private.pem` is stored safely (NOT in the repo).
- [ ] ZIP contains only `manifest.json`, `background.js`, `sidepanel.html`, `sidepanel.js` (no `.secret`, no `.pem`, no `.DS_Store`).
- [ ] Privacy tab filled in (single purpose, per-permission justification, "no remote code", "no data collection").
- [ ] Screenshots + 128×128 icon ready.
- [ ] LaunchAgent template updated with the **published** extension ID (so `install.sh` doesn't need to ask).
- [ ] `install.sh` (optional) written to automate §4's user flow.
