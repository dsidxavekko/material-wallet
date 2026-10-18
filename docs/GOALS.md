# Material Wallet — analysis and project goals

Date: 18 October 2026 · version in `pubspec.yaml`: `0.4.0+5`

This document has four parts: the main goal and the principles that must not
be broken; what already exists; what was found during the review (facts from
the code and from live API responses); and the goals, ordered by value versus
effort. The original Ukrainian version is in [`ЦІЛІ.md`](ЦІЛІ.md).

---

## 1. Main goal

Take the wallet from "shows everything, signs EVM and Bitcoin" to **"every
number on screen is true, every send is verified, and every network the app
shows can actually send"** — without breaking any of the principles below.

The principles are constraints on every goal in this document:

1. **Keys never leave the device.** The private key is derived for one
   signature and then wiped.
2. **No backend and no API keys** — only public, key-less APIs.
3. **Own signing in pure Dart**, pinned by external test vectors (BIP-143,
   EIP-155, BIP-39) and a live check that spends nothing
   (`tool/verify_eip1559.dart`).
4. **Re-read live state right before signing**: balance, token holding, UTXOs.
5. **Honest errors**: no hash means "Nothing was sent".

---

## 2. What exists now

| | |
|---|---|
| Size | `lib/` ≈ 15.4k lines, `test/` ≈ 5.6k, ~258 tests |
| Networks | 10: Bitcoin (+ testnet), Ethereum, Sepolia, Base, Polygon, Arbitrum, BNB, Solana, Aptos |
| Sending | EVM (EIP-1559, ERC-20, speed-up / cancel, revoke) and Bitcoin (P2WPKH). BNB, Solana, Aptos — view only |
| Security | AES-256-GCM + PBKDF2 600k, 6–8 digit PIN, biometrics, auto-lock, backoff after wrong PINs, `FLAG_SECURE`, re-authentication before every send |
| Providers | mempool.space, Blockscout, CoinGecko, publicnode, Solana RPC, Aptos fullnode |
| `ponytail:` markers | 3 |

Three things are done unusually well:

1. **The live-state check lives in one place** — `SendController`, so every
   caller gets it, not only the Send screen.
2. **Signing is pinned to vectors**, not "works on my phone": the BIP-143
   sighash matches byte for byte, and EIP-1559 was verified on a live Sepolia
   node.
3. **Comments explain "why"**, and known limits are marked honestly with
   `ponytail:`.

---

## 3. What the review found

Facts taken from the code and from live API responses on 18 October 2026.

### 3.1. Wrong numbers on the home screen

> **Updated 2026-10-18:** all three items are fixed (goals A1–A3 in §4): rates
> come live from CoinGecko (all three in one request), the portfolio counts
> tokens, and the version is a single constant verified by a test.

- **Fiat rates are constants.** `formatters.dart:8–10`: EUR 0.92, UAH 41.5,
  with the comment "static demo values". CoinGecko today: 1 USD ≈ 0.890 EUR,
  ≈ 44.92 UAH. The hryvnia balance is understated by **~7.6%**, the euro
  balance overstated by ~3.4%.
- **"Total across networks" ignores tokens.** `wallet_controller.dart:116`
  sums `fiatBalance` — the native balance × price (`chain_models.dart:219`).
  $1000 in USDC + $5 in ETH → the screen shows **$5**. It also only covers
  networks the user has already opened.
- **The version in Settings is stale.** `settings_screen.dart:1010` shows
  `0.3.0 (4)`, while `pubspec.yaml` says `0.4.0+5`. Commit `db150a7` fixed
  this once; while the number is hardcoded it will drift with every release.

### 3.2. Activity does not show everything

- **Token transfers are invisible.** Only `/addresses/{a}/transactions` is
  read (`chain_api.dart:108`). An incoming USDC transfer never appears; an
  outgoing ERC-20 transfer, an approve or a revoke looks like "Sent ETH" for
  the fee amount, with the token contract recorded as the recipient. Blockscout
  has `/addresses/{a}/token-transfers` (checked: `from`, `to`, `total`,
  `token`, `transaction_hash`, 50 per page).
- **Only the first page is loaded.** Blockscout — 50 items, mempool.space — up
  to 25 confirmed, Solana — 6 (`chain_api.dart:959`), Aptos — 15 (`:1122`).
  `next_page_params` is present in responses but ignored.
- The CSV export inherits both gaps, so it is not usable for a tax report yet.

### 3.3. "Transfer confirmed" only arrives after a manual refresh

`WalletController` has no timer: data is reloaded only when the (network,
address) pair changes or on pull-to-refresh. The success screen waits for a
receipt for ~90 s on EVM (12 attempts, 2…13 s) and ~3.2 min on Bitcoin
(5…27 s) — less than an average block. After that nothing polls the network,
so the notification fires only when the user refreshes the list. The note at
`confirmation_watcher.dart:17` ("while the app is running") is more optimistic
than reality.

### 3.4. Payment links and the scanner

- **The scanner drops the amount and breaks on chain ids.** `_extractAddress`
  (`send_screen.dart:530`) takes only `uri.path`: from `bitcoin:bc1…?amount=0.5`
  the amount disappears, and `ethereum:0x…@137` becomes an "invalid address".
  A parser that handles both cases already exists — `parsePaymentLink` — but it
  is called only for deep links (`app.dart:145`).
- **An EIP-681 payment request for a token becomes an ETH send to the token
  contract.** `payment_link.dart:39–46` strips `@chainId` and `/transfer`, so
  `ethereum:<USDC>@1/transfer?address=<merchant>&uint256=…` turns into:
  recipient = USDC contract, currency = ETH, amount empty. The merchant
  receives nothing; at best the transaction reverts and spends gas.
  `payment_link_test.dart` has no case for this.

### 3.5. Bitcoin: a stuck transfer cannot be rescued

- Presets are multipliers of `halfHourFee` (`send_controller.dart:51`: Slow =
  ½, Fast = ×2), although mempool.space returns ready-made tiers
  `fastestFee`, `halfHourFee`, `hourFee`, `economyFee`, `minimumFee` (checked).
- Inputs are signed with `sequence = 0xffffffff` (`bitcoin_signer.dart:47`),
  so RBF (BIP-125) is not signalled, and "Speed up" exists only for EVM
  (`replace_transfer.dart:194–201`). "Slow" during a fee spike can get stuck
  with no way out inside the app.

### 3.6. EVM replacement limits rest on an outdated assumption

The `ponytail:` note in `replace_transfer.dart:38` and the comment on
`replacementKindsFor` (lines 181–184) say the history API exposes neither the
fee cap of a stuck transaction nor its calldata. Blockscout v2 today returns
`max_fee_per_gas`, `max_priority_fee_per_gas`, `gas_limit` and `raw_input`
(checked on Ethereum). That means:

- a replacement can be priced from the original's fee (+10%, the geth
  replacement rule), not from "the fast preset, hopefully enough";
- speed-up can be offered for ERC-20 transfers and approvals too, using the
  same `raw_input`.

For pending transactions, these fields must be verified separately: they come
from the mempool index.

### 3.7. One RPC per network — a single point of failure

Each EVM network has exactly one `sendRpcUrl`, all on `*.publicnode.com`. From
this machine, every request to publicnode returns a `*.o2.cz` certificate (the
local network's DNS resolves elsewhere). In that environment the wallet shows
balances (Blockscout works) but **cannot send on any EVM network**, and the
BNB balance does not load at all.

### 3.8. The PIN is weaker than "600,000 rounds" suggests

PBKDF2 with 600k rounds is the right figure for passwords, but a PIN is 6–8
digits (`pin_field.dart`: `digitsOnly`, `maxLength: 8`). An RTX 4090 computes
PBKDF2-HMAC-SHA256 at roughly 8.9 million/s with 999 iterations (hashcat, mode
10900) → about 15 thousand PIN guesses per second at 600k. **Every 6-digit PIN
falls in about a minute, 8-digit PINs in about 2 hours**, once the encrypted
vault is in an attacker's hands (root access, forensics, web storage).

The real protection is the Android Keystore via `flutter_secure_storage`, plus
`allowBackup="false"`, not the KDF. Biometrics is a UI gate: the PIN is stored
in the same vault without binding the key to authentication
(`secure_pin_store.dart`). For a phone this is a common hot-wallet model; for
the web build, where storage is the browser, it is not. The README should say
so directly.

### 3.9. Smaller items

- Address-poisoning checks run only on EVM (`send_screen.dart:179`).
  `AddressGuard` itself is network-neutral; for bech32 only the `bc1q` / `tb1q`
  prefix needs to be skipped.
- BNB Chain has `chainId: 56` but no `sendRpcUrl` — view only.
  `tool/verify_eip1559.dart` is hardwired to Sepolia constants (lines 22–23).
- "Hide balance" is not persisted across launches and does not apply to
  Activity (`home_screen.dart:36`).
- Accounts have no names ("Account 2 of 3"), and an account cannot be hidden.
- About → "Data sources" lists 3 of the 6 providers
  (`settings_screen.dart:1021`), although each of the six sees the user's IP
  and addresses.
- A separate scam-token filter is **not needed**: Blockscout v12+ already
  filters known scam tokens (in a sample of 50 tokens, all had
  `reputation: ok`). A manual "hide token" option is enough.

---

## 4. Goals

Grouped into milestones. Effort is a rough estimate. "Done when" is the
criterion a test can verify.

### Milestone A — "Honest numbers" · ~3 days

**A1. Live fiat rates** · 1–2 h · done 2026-10-18
Same request in `price_api.dart`, but with `vs_currencies=usd,eur,uah` —
CoinGecko returns all three in one call (checked). Rate = eur/usd, uah/usd; the
constant stays as a fallback in case of 429.
*Done when:* a test with a canonical response gives a hryvnia balance equal to
the UAH price × balance.

**A2. Portfolio with tokens** · 1–2 h · done 2026-10-18
`_refreshPortfolio()` adds token `usdValue`; tokens without a rate are not
counted.
*Done when:* a test: $5 in ETH + $1000 in USDC = $1005.

**A3. Version from one place** · 30 min · done 2026-10-18
One constant plus a test that reads `pubspec.yaml` and compares. No new
dependency.

**A4. Scanner and paste go through `parsePaymentLink`** · 1–2 h
The amount from the link is filled in; a link for another network offers to
switch, instead of silently replacing the network.
*Done when:* a widget test: scanning `bitcoin:…?amount=0.5` fills the amount
field with `0.5`.

**A5. EIP-681 for tokens** · half a day
`ethereum:<token>@<id>/transfer?address=…&uint256=…` opens
`SendScreen(token: …)` with recipient and amount, if the token is in the
balance; otherwise it refuses with an explanation. Any other `/function` is
refused.
*Done when:* new cases in `payment_link_test.dart`, including "unknown token".

**A6. Polling while something is pending** · 2–3 h
A timer in `WalletController` (EVM ~20 s, Bitcoin ~60 s) runs only while the
snapshot contains an outgoing pending transaction; it stops on lock, dispose
and network change. The price cache (60 s) already protects CoinGecko.
*Done when:* a test with a fake `ChainApi`: pending → confirmed after N ticks →
exactly one notification.

**A7. Token transfers in Activity + "Load more"** · 1–2 days
`/token-transfers` is merged with the native list by hash: the row "Sent ETH
−fee" becomes "Sent 100 USDC", the fee stays. `ChainTransaction` gets optional
token fields (old cache still reads fine); paging via `next_page_params`; the
cache keeps only the first page. The CSV gets a separate fee-ticker column.
*Done when:* tests for the merge and for reading an old cache without the new
fields.

### Milestone B — "Safer sending" · ~4 days

**B1. Recipient check before signing** · half a day to a day · **biggest
safety gain per hour of work**

One GET to `{apiBase}/addresses/{to}` on Blockscout networks (checked:
`is_contract`, `is_scam`, `token`, `ens_domain_name`):

| signal | reaction |
|---|---|
| `is_scam: true` | red warning |
| `token` is set — the address is a token contract | red: funds sent to a token contract are usually lost |
| token transfer to the token's own address | block; checked locally, no network needed |
| `is_contract` (Safe, exchange) | information, not a block |
| request failed | "Could not verify this address" — never a silent "ok" |

Integration point: `_prepare()` in `send_screen.dart`, before
`_PreparedSheet`; new `ChainApi.fetchAddressInfo`.
*Done when:* a test for each row of the table with canonical responses.

**B2. Bitcoin: real fee tiers** · 1–2 h
Slow → `hourFee`, Normal → `halfHourFee`, Fast → `fastestFee`.

**B3. Bitcoin: RBF** · signalling is one line; Speed up is 1–2 days
`sequence = 0xfffffffd` in `signP2wpkh` (the BIP-143 vector sets its own
sequence values, so it stays valid). Speed up: `GET /tx/{txid}` → the same
inputs and recipient, new fee taken from change (BIP-125 rules: higher absolute
fee and a bump for the extra size); if change is not enough, refuse clearly.
*Done when:* a unit test of the replacement plan, and a transfer at 1 sat/vB
replaced and confirmed on testnet.

**B4. Honest EVM replacement (3.6)** · half a day
Replacement price = max(fast preset, original × 1.1); speed-up for ERC-20 and
approve uses the original's `raw_input`. Remove the two outdated notes.
*Done when:* a test: replacement is always ≥ 110% of the original, and calldata
is byte-identical to `raw_input`.

**B5. Poisoning check on all networks** · 1–2 h
`AddressGuard` skips `bc1q` / `tb1q`; remove the "EVM only" condition.

**B6. Password instead of PIN — your decision (3.8)** · a day
The vault format does not change (the PIN is just a string for PBKDF2); only
the UI changes: `PinField`, creation, unlock, PIN change. An option, not a
requirement.

### Milestone C — "Real multi-chain" · ~2 weeks

**C1. Fallback RPC endpoints (3.7)** · half a day
`sendRpcUrl` → a list. Move to the next node only on a network error, not on a
JSON-RPC error. "already known" on a repeated `eth_sendRawTransaction` counts as
success: identical signed bytes produce the same hash.
*Done when:* a test: the first node fails, the second accepts, and the hash is
the same.

**C2. Portfolio screen across all networks** · 1–2 days
One price request for all coins (`ids=bitcoin,ethereum,…` — checked), balances
in parallel, tokens; the list sorted by value, tap to switch network. Replaces
"check ten networks to see the total".

**C3. SPL tokens (roadmap)** · a day
`getTokenAccountsByOwner` (jsonParsed, Token and Token-2022 programs) →
`TokenBalance`.

**C4. Sending SOL (roadmap)** · 3–5 days
Legacy message (header, compact-u16, `getLatestBlockhash`, System Program
transfer instruction), ed25519 — `ed25519_edwards` is already a dependency,
`sendTransaction`, `getSignatureStatuses`. Pitfall: a new recipient account must
receive at least the rent-exempt minimum (890,880 lamports ≈ 0.00089 SOL), and
the sender's remaining balance must not fall between zero and that minimum.
Add Solana devnet for verification.
*Done when:* a serialisation test vector + `simulateTransaction` with
`sigVerify` on devnet — the equivalent of `verify_eip1559.dart`.

**C5. Sending APT (roadmap)** · 3–4 days
BCS `RawTransaction` (sequence_number from `/accounts/{a}`,
`0x1::aptos_account::transfer`, gas, expiration, chain_id); the message to sign
= `sha3_256("APTOS::RawTransaction") ‖ bcs`; POST `/transactions` as
`application/x.aptos.signed_transaction+bcs`. Start with
`/transactions/simulate`.
*Done when:* a BCS test vector + a successful simulation on testnet.

**C6. Sending BNB** · 2 h + verification
`sendRpcUrl` + `verify_eip1559.dart`, parameterised for BSC testnet (chainId
97). Without history there will be no speed-up, no notifications and no
history-based poisoning check on this network — the UI must say so.

### Milestone D — "Convenience" · each goal at most a day

| goal | effort | note |
|---|---|---|
| D1. Payment request: amount in Receive → QR with BIP-21 / EIP-681 / Solana Pay / `aptos:` + Share | half a day | `share_plus` is already there; round-trip test through `parsePaymentLink` |
| D2. Fiat amount in Send | half a day | after A1; the amount is signed in coins, shown on review |
| D3. Account names | 2–3 h | `shared_preferences`, account picker in Settings |
| D4. Privacy mode that persists and applies everywhere | 2 h | `_hideBalance` → `SettingsController` |
| D5. Local notes on transactions, included in CSV | half a day | hash → text map |
| D6. ENS (`name.eth`) in the recipient field | a day | eth_call to the Universal Resolver; the resolved address is shown on review and passes B1 |
| D7. Search in Activity by address, label or hash | 2–3 h | after A7 |
| D8. Full provider list in About | 10 min | see 3.9 · done 2026-10-18 |

### Larger ideas — separate branches

- **Watch-only addresses** — follow a cold wallet without keys. Requires
  separating "address" from "seed" in `WalletIdentityController`.
- **Multiple seed phrases** — currently one vault per device.
- **Background notifications** via WorkManager — a new dependency and battery
  cost, but a real "you received funds" while the app is closed.
- **Ukrainian localisation** — all strings are currently English in code;
  2–3 days of mechanical ARB work.
- **Biometrics with cryptographic binding** (a Keystore key requiring user
  authentication) — needs a different plugin than `local_auth`.

---

## 5. Recommended order

| # | What | Effort | Why here |
|---|---|---|---|
| 1 | A1, A2, A3, D8 | half a day | wrong numbers on the home screen; no risk |
| 2 | A4, A5 | half a day | errors where money moves |
| 3 | B1 | half a day to a day | largest safety gain; the data is already in Blockscout |
| 4 | A6 | 2–3 h | makes the existing notifications actually work |
| 5 | B2, B3 (signalling), B4, B5 | a day | EVM replacement becomes reliable, Bitcoin fee tiers become real |
| 6 | A7 | 1–2 days | Activity and CSV become truthful |
| 7 | C1, D1 | a day | resilience to an unavailable RPC + the most visible small feature |
| 8 | B3 (Speed up), C2 | 2–4 days | Bitcoin can be rescued too; the portfolio becomes a multi-chain screen |
| 9 | C3 → C4 → C5 → C6 | ~2 weeks | closes the roadmap: every network shown can send |
| 10 | D2–D7, B6 | as needed | |

The first four rows are about two days of work, after which the wallet stops
showing wrong amounts and catches the most expensive sending mistakes.

---

## 6. What I would not do

- **WalletConnect / dApp browser.** Requires a Reown project ID and their relay
  — that means a key and a third-party backend. It is also the main channel for
  signing malicious approvals, which the Token approvals screen exists to
  guard against.
- **Swaps via aggregators** — most require an API key; plus MEV and
  regulation.
- **Cloud backup of the encrypted seed.** With a 6-digit PIN (3.8) such a file
  can be brute-forced in a minute.
- **Replacing our own signing with large libraries** (web3dart etc.). The
  project's value is ~800 lines of in-house signing (`evm_signer.dart`,
  `bitcoin_signer.dart`) pinned by vectors.
- **Own push server** — breaks "no backend".

---

## 7. What to keep through any change

1. **Re-check live state before signing** — for every new network, following
   the pattern of `SendController.send` / `sendBitcoin`.
2. **The key is derived for one signature and wiped** (`fillRange`); the seed is
   copied.
3. **Every new signing path comes with an external vector and a live check
   that spends nothing.**
4. **Every action that moves funds goes through `authorizeSensitiveAction`.**
5. **Advisory checks (B1, poisoning) never fail silently** — they say "could not
   verify".
6. **A new data provider is added to About immediately.**
7. **Known limits are marked with a `ponytail:` comment next to the code, and
   the marker is updated together with the code.** Sections 3.3 and 3.6 show
   that markers go stale.
