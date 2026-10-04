# Material Wallet

A modern, **self-custodial** cryptocurrency wallet built with Flutter and
Material 3. Your keys never leave the device: the BIP-39 recovery phrase is
generated locally, encrypted, and stored only on this device.

> ⚠️ **Disclaimer**
> This project is a **portfolio / educational app**. It derives real public
> addresses and reads live on-chain data, but the *Send* flow only **validates
> and estimates a fee** — it does **not** sign or broadcast transactions yet.
> **Do not use it to store meaningful funds.**

---

## Features

- 🔑 **Create wallet** — generates a BIP-39 recovery phrase (12 or 24 words) with
  an on-screen verification step.
- 📥 **Import wallet** — restore from an existing BIP-39 phrase.
- 🔒 **Security first**
  - Recovery phrase encrypted with **AES-256-GCM**, key derived via
    **PBKDF2-HMAC-SHA256** (600,000 rounds, OWASP 2023 guidance).
  - 6-digit PIN lock, changeable in Settings.
  - **Biometric unlock** (fingerprint / face) via `local_auth`.
  - Screenshots and the app-switcher preview are blocked (`FLAG_SECURE`).
- 🌐 **Multi-chain** — Bitcoin, EVM networks, Solana and Aptos (see table below).
- 💸 **Send (dry-run)** — validates the address, checks the live balance and
  fetches the real network fee; does not sign or broadcast.
- 📷 **Receive** — real address as text and a scannable QR code.
- 🔍 **QR scanner** — scan a recipient address with the camera.
- 📊 **Live balance, activity & prices** — balances/history from public key-less
  APIs, prices from CoinGecko (cached to respect rate limits).
- 🎨 **Material 3 UI** — light / dark / system theme, multiple display currencies.
- 🧪 **Tested** — unit and widget tests covering derivation, crypto and APIs.

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

- The recovery phrase is **never** written to disk in the clear. It is encrypted
  with a key derived from the user's PIN and only decrypted into memory after a
  successful unlock.
- The encrypted vault is a small self-describing JSON blob, so the KDF
  parameters can be raised later without breaking existing wallets.
- Because AES-GCM is authenticated, a wrong PIN cannot silently "succeed": the
  tag check fails and decryption is rejected.
- On the web build, the heavy PBKDF2 derivation runs through the browser's
  **Web Crypto API** so the UI does not freeze.
- When biometric unlock is enabled, the PIN is kept in the platform keystore
  (`flutter_secure_storage`) and released only after a successful biometric
  prompt.

---

## Tech stack

- **Flutter 3.47** / **Dart 3.13**, Material 3.
- **provider** for state management.
- **pointycastle** (AES-GCM, PBKDF2), **bip39**, **bip32**, **ed25519_edwards**
  for key material and derivation.
- **flutter_secure_storage** + **local_auth** for secure PIN storage / biometrics.
- **qr_flutter** + **mobile_scanner** for QR codes.
- **http** + **intl** for networking and formatting.

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
```

---

## Roadmap

- [ ] Sign and broadcast transactions (Bitcoin, EVM, Solana, Aptos).
- [ ] Token balances (ERC-20 / SPL) and NFT display.
- [ ] Address book and contact labels.
- [ ] Biometric-protected reveal of the recovery phrase.

---

## License

Released under the **MIT License** — see [`LICENSE`](LICENSE).

---

*Built as a learning project — contributions and feedback are welcome.*
