# Material Wallet

A modern, **self-custodial** cryptocurrency wallet built with Flutter and
Material 3. Your keys never leave the device: the BIP-39 recovery phrase is
generated locally, encrypted, and stored only on this device.

> ⚠️ **Disclaimer**
> This project is a **portfolio / educational app**. It derives real public
> addresses, reads live on-chain data, and **signs and broadcasts real EVM and
> Bitcoin transactions** on-device. Solana and Aptos send flows still only
> validate and estimate a fee.
> **Do not use it to store meaningful funds.**

---

## Features

- 🔑 **Create wallet** — generates a BIP-39 recovery phrase (12 or 24 words) with
  an on-screen verification step.
- 📥 **Import wallet** — restore from an existing BIP-39 phrase, with optional
  support for a **passphrase (25th word)**: the phrase and the passphrase are
  both encrypted into the vault and both are needed to restore.
- 👥 **Multiple accounts** — BIP-44 account indexes from the same seed, each with
  its own address on every chain, switchable from Settings.
- 🔒 **Security first**
  - Recovery phrase encrypted with **AES-256-GCM**, key derived via
    **PBKDF2-HMAC-SHA256** (600,000 rounds, OWASP 2023 guidance).
  - Password lock (min. 8 characters; older 6–8 digit PINs keep working), changeable in Settings.
  - **Biometric unlock** (fingerprint / face) via `local_auth`.
  - **Auto-lock** after a configurable time in the background, and
    **attempt throttling** with escalating backoff after wrong PINs.
  - Sending, replacing a transaction and revoking an approval all require
    re-authentication: a **fingerprint when biometric unlock is enabled**,
    otherwise the PIN.
  - The live balance — and a token holding, read on-chain — is re-checked right
    before signing, so a transfer is never signed against a stale number.
  - Revealing the recovery phrase requires re-authentication, and a copied
    phrase is wiped from the clipboard automatically.
  - Screenshots and the app-switcher preview are blocked (`FLAG_SECURE`).
- 🌐 **Multi-chain** — Bitcoin, EVM networks, Solana and Aptos (see table below).
- 💸 **Send** — validates the recipient address per chain (bech32, Base58Check,
  EIP-55, Aptos hex) against the live balance, with **native and ERC-20**
  transfers and Low/Normal/High/**custom** fee presets. On **EVM networks** the
  transfer is signed on-device as an **EIP-1559** (type-2) transaction with a
  fee cap (EIP-2, RFC-6979), re-checks the live balance right before signing,
  and is broadcast for real after a PIN confirmation, ending on a full-screen
  success screen; other chains stop at a copyable summary. On **Bitcoin** the
  transfer is a native SegWit (**BIP-143 P2WPKH**) transaction: utxos are
  selected for the entered amount, change returns to your address, the fee is
  priced in sat/vB with the same presets, and the signed transaction is
  broadcast through mempool.space.
- 📒 **Address book** — save recipients with local labels; labels show up in the
  send flow and the activity list.
- 🪙 **Token balances** — ERC-20 holdings with USD values on the Blockscout-backed
  EVM networks; tap a token to send it.
- ↩️ **Fix a stuck transfer** — replaces a pending outgoing EVM transaction with
  one that reuses its nonce, either as a **speed-up** (same transfer, higher
  fee) or a **cancel** (zero-value self-transfer that can never confirm). The
  replacement is priced from the stuck transaction's own fee cap plus 10 % (the
  node's rule), and a speed-up of an ERC-20 transfer or approval reuses the
  original calldata byte for byte.
- 🔓 **Token approvals** — lists what contracts are allowed to spend your
  tokens and can revoke each one (`approve(spender, 0)`), the only in-wallet way
  to undo a malicious approval.
- 🕵️ **Address poisoning warning** — on every chain, before sending, a recipient
  whose first and last characters copy an address this wallet already deals
  with is flagged: the scam pattern where a worthless token arrives from an
  address built to look like a contract you trust.
- 🛟 **Recipient check before signing** — on Blockscout-backed EVM networks the
  recipient is looked up right before the signature, so a scam-tagged address,
  a token contract (funds sent there are usually lost) or a token sent to its
  own contract are caught while the transfer can still be stopped. If the lookup
  fails, the send sheet says the address could not be verified rather than
  staying silent.
- 🔔 **Confirmation notifications** — a local notification when an outgoing
  transfer confirms, even after a restart; while a transfer is pending the
  wallet re-reads the chain on its own (EVM ~20 s, Bitcoin ~60 s) so the
  notification arrives without a manual refresh.
- 🔗 **Payment links** — `bitcoin:`, `ethereum:` (EIP-681), `solana:` and
  `aptos:` URIs open the app and prefill the send flow.
- 🧮 **Portfolio total** — the account's value summed across every network it has
  synced, priced ERC-20 holdings included, shown on the home screen.
- 📷 **Receive** — real address as text and a scannable QR code.
- 🗂️ **Your addresses** — every chain's receive address in one place, each with
  a QR code and a verify-against-a-second-device warning.
- 🔍 **QR scanner** — scan a recipient address with the camera.
- 📊 **Live balance, activity & prices** — balances/history from public key-less
  APIs, prices from CoinGecko (cached to respect rate limits). The last snapshot
  is cached locally **per account**, so the app opens with data and works
  offline.
- 🧾 **CSV export** — share the loaded activity as a CSV file straight from the
  share sheet.
- 🎨 **Material 3 UI** — light / dark / system theme (persisted), multiple
  display currencies.
- 🧪 **Tested** — unit and widget tests covering derivation, crypto, address
  validation, storage and APIs.

---

## Screenshots

| Wallet                          | Activity                          | Send                          |
| ------------------------------- | --------------------------------- | ----------------------------- |
| ![Wallet](screenshots/03-wallet.png) | ![Activity](screenshots/05-activity.png) | ![Send](screenshots/04-send.png) |

| Onboarding                          | Unlock lock screen                | Settings                          |
| ----------------------------------- | --------------------------------- | --------------------------------- |
| ![Onboarding](screenshots/01-onboarding.png) | ![Lock](screenshots/02-lock.png) | ![Settings](screenshots/06-settings.png) |

> The screens were rendered headlessly in the widget-test harness
> (`flutter test tool/screenshots_test.dart --update-goldens`) with a
> deterministic test phrase and canned network responses — no real funds.

---

## Supported networks

| Group   | Network        | Address standard      | Data source                     |
| ------- | -------------- | --------------------- | ------------------------------- |
| Bitcoin | Bitcoin        | BIP-84 (`bc1q…`)      | mempool.space                   |
| Bitcoin | Bitcoin Testnet| BIP-84 (`tb1q…`)      | mempool.space                   |
| EVM     | Ethereum       | BIP-44 (`0x…`, EIP-55)| Blockscout                      |
| EVM     | Base           | BIP-44                | Blockscout                      |
| EVM     | Polygon        | BIP-44                | Blockscout                      |
| EVM     | Arbitrum One   | BIP-44                | Blockscout                      |
| EVM     | BNB Chain      | BIP-44                | public JSON-RPC (no history)    |
| EVM     | Sepolia (test) | BIP-44                | Blockscout                      |
| Solana  | Solana         | SLIP-0010 (ed25519)   | Public Solana RPC               |
| Aptos   | Aptos          | SLIP-0010 (ed25519)   | Public Aptos fullnode           |

> All balance/history endpoints are **free and key-less** public APIs, so the
> app needs no API keys and no backend.

---

## How the wallet stays safe

- The recovery phrase — and the optional BIP-39 passphrase — are **never**
  written to disk in the clear. They are encrypted together with a key derived
  from the user's PIN and only decrypted into memory after a successful unlock.
- The encrypted vault is a small self-describing JSON blob, so the KDF
  parameters can be raised later without breaking existing wallets.
- Because AES-GCM is authenticated, a wrong PIN cannot silently "succeed": the
  tag check fails and decryption is rejected.
- On the web build, the heavy PBKDF2 derivation runs through the browser's
  **Web Crypto API** so the UI does not freeze.
- When biometric unlock is enabled, the PIN is kept in the platform keystore
  (`flutter_secure_storage`) and released only after a successful biometric
  prompt.
- The vault is re-locked after a configurable period in the background, and
  repeated wrong PINs are penalised with an escalating, persisted backoff.
- The seed is overwritten in memory on lock. Non-secret data (settings, the
  address book, the active account index and the last account snapshots) lives
  in `shared_preferences`.

---

## Tech stack

- **Flutter 3.47** / **Dart 3.13**, Material 3.
- **provider** for state management.
- **pointycastle** (AES-GCM, PBKDF2, ECDSA), **bip39**, **bip32**,
  **ed25519_edwards** for key material and derivation. Bitcoin transactions are
  built and signed against the **BIP-143** sighash; EVM transactions use
  **RLP** + **EIP-1559**.
- **flutter_secure_storage** + **local_auth** for secure PIN storage / biometrics.
- **qr_flutter** + **mobile_scanner** for QR codes.
- **http** + **intl** for networking and formatting, **share_plus** for the CSV
  export.

---

## Getting started

```bash
# 1. Install dependencies
flutter pub get

# 2. Run on a connected device / emulator
flutter run

# 3. Run the test suite
flutter test

# 4. Static analysis
flutter analyze

# 5. Build (examples)
flutter build apk --release     # Android
flutter build web --release     # Web
```

**Requirements:** Flutter 3.47+ with Dart 3.13+. For Android builds you also need
an Android SDK and a JDK 17 toolchain (`android/local.properties` is generated
by the Flutter tool and is intentionally git-ignored).

The EIP-1559 signing path can be checked against a live Sepolia node without
spending anything: `dart run tool/verify_eip1559.dart` signs a type-2 transfer
with a throwaway key and confirms the node decodes it and recovers the sender.

The Bitcoin path is pinned to the published **BIP-143 P2WPKH vector** in
`test/bitcoin_signer_test.dart`: the sighash must match byte-for-byte, and the
DER signature must verify against the public key.

---

## Project structure

```
lib/
├── main.dart                 # Entry point
├── app.dart                  # Root widget, providers, routing gate
├── core/
│   ├── crypto/               # bech32, base58, slip-10, hashing
│   ├── theme/                # Material 3 themes & colors
│   └── utils/                # formatters, units, explorer links
├── data/
│   ├── models/               # chain kinds
│   ├── networks/             # network config, chain & price APIs
│   └── wallet/               # seed vault, address deriver, storage, biometrics
├── features/                 # onboarding, lock, home, send, receive,
│                             # activity, settings, scan, network pickers
├── shared/widgets/           # reusable UI widgets
└── state/                    # controllers (settings, identity, wallet)
docs/
├── GOALS.md                  # analysis and development goals (English)
└── ЦІЛІ.md                   # the same document in Ukrainian (original)
```

---

## Roadmap

- [x] Sign and broadcast transactions (EVM) — verified end-to-end on Sepolia.
- [x] Sign and broadcast Bitcoin transfers (BIP-143 P2WPKH, BIP-84 keys).
- [ ] Sign and broadcast transactions (Solana, Aptos).
- [x] EIP-1559 typed transactions with a fee cap.
- [x] Reject a transfer whose live balance dropped since the last refresh.
- [ ] SPL token balances.
- [x] Biometric (not only PIN) re-auth for revealing the recovery phrase.
- [x] Biometric (not only PIN) re-auth before sending, replacing a transaction
      and revoking an approval.
- [x] Revoke ERC-20 approvals.
- [x] Speed up a stuck EVM transaction (replace-by-fee, same nonce).
- [x] Re-check the live token holding before signing a token transfer.
- [x] Address poisoning warning in the send flow.
- [x] BIP-39 passphrase (25th word) support — encrypted alongside the phrase in
      the vault, applied to every derivation (BIP-39 reference vector pinned).
- [ ] Known-answer test vectors for the address derivations beyond the ones
      already pinned (BIP-32 test vectors per coin type).

### Next: honest numbers (milestone A)

- [x] Live fiat rates for USD / EUR / UAH (replace the static demo rates).
- [x] Portfolio total includes ERC-20 holdings.
- [x] Single source of truth for the app version (About screen).
- [x] Scanner and paste read the amount and chain id from payment links.
- [x] EIP-681 token payment links open a token transfer, or refuse clearly.
- [x] Pending transfers are polled, so "Transfer confirmed" fires without a
      manual refresh.
- [ ] Token transfers, approvals and reverts appear in Activity, with paging.

### Safer sending (milestone B)

- [x] Recipient check before signing: flags scam-tagged addresses, token
      contracts and token-transfer targets (Blockscout).
- [x] Bitcoin fee presets from the node's fastest / half-hour / hour rates.
- [ ] Bitcoin RBF (BIP-125) signalling and Speed up.
- [x] EVM replacements priced from the original transaction (≥ 110 %) and
      applied to token transfers and approvals too.
- [x] Address poisoning check on every chain, not only EVM.
- [x] Password instead of the 6–8 digit PIN (min. 8 characters; the vault format is unchanged, so old PINs still unlock).

### Multi-chain (milestone C)

- [ ] Fallback RPC endpoints for EVM broadcasting.
- [ ] Single portfolio screen across all networks.
- [ ] Solana SPL tokens, then SOL sending (validated on devnet).
- [ ] Aptos APT sending (BCS, validated by simulation on testnet).
- [ ] BNB Chain sending (BSC testnet first).

### Convenience

- [ ] Receive screen with a BIP-21 / EIP-681 / Solana Pay / `aptos:` request
      and QR share.
- [ ] Fiat amount in Send, account names, persistent balance hiding.
- [ ] Local notes on transactions, included in the CSV export.
- [ ] ENS names in the recipient field.

Full analysis, reasons and acceptance criteria: [`docs/GOALS.md`](docs/GOALS.md)
(English) · [`docs/ЦІЛІ.md`](docs/ЦІЛІ.md) (original, Ukrainian).

---

## License

Released under the **MIT License** — see [`LICENSE`](LICENSE).

---

*Built as a learning project — contributions and feedback are welcome.*
