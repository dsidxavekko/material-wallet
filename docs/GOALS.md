# Material Wallet — analysis and project goals

Date: 18 October 2026 (updated 19 October 2026 — every goal in §4 is implemented in code, the live checks were run the same day (§8), and milestone F — watch-only, several recovery phrases, hardware-bound fingerprint, background notifications, hidden tokens in totals — was added and built) · version in `pubspec.yaml`: `0.5.0+6`

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
| Size | `lib/` ≈ 22.9k lines, `test/` ≈ 10.7k, 476 tests, 283 lines of Kotlin |
| Networks | 11: Bitcoin (+ testnet), Ethereum, Sepolia, Base, Polygon, Arbitrum, BNB, Solana (+ Devnet), Aptos |
| Sending | every network: EVM and BNB (EIP-1559, ERC-20, speed-up / cancel, revoke), Bitcoin (P2WPKH, RBF speed-up), SOL and APT (native coin). SPL tokens — view only |
| Wallets | several recovery phrases in one vault under one password; watch-only wallets (no key, no password of their own) |
| Security | AES-256-GCM + PBKDF2 600k, password of at least 8 characters (old 6–8 digit PINs still unlock), fingerprint unlock bound to an Android Keystore key (per-use authentication), auto-lock, backoff after wrong PINs, `FLAG_SECURE`, re-authentication before every send |
| Providers | mempool.space, Blockscout, CoinGecko, PublicNode, dRPC, 1RPC, official RPCs (Base, Arbitrum, Polygon, BNB), Solana RPC, Aptos fullnode |
| `ponytail:` markers | 7 |
| Automation | GitHub Actions: `flutter analyze` + `flutter test` and a debug build of the Android app on every push and PR; a manual workflow runs the no-spend live checks of §8 |

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

> **Updated 2026-10-19:** fixed (goal A7 in §4): token transfers are merged into the native list, there is "Load more" on all four chain types, and the CSV has separate fee-ticker and note columns.

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

> **Updated 2026-10-18:** fixed (goal A6 in §4). `WalletController` now polls
> while the snapshot holds an outgoing pending transfer (EVM ~20 s, Bitcoin
> ~60 s), stopping on lock, dispose and network change; the optimistic note in
> `confirmation_watcher.dart` was corrected to match.

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

> **Updated 2026-10-19:** RBF (second bullet) is done — goal B3 in §4: inputs are signed with `sequence = 0xfffffffd` and "Speed up" exists. A live testnet confirmation of a replacement has not been run yet.

> **Updated 2026-10-18:** the presets now use mempool.space's real tiers (goal
> B2 in §4): Slow → `hourFee`, Normal → `halfHourFee`, Fast → `fastestFee`.
> RBF (second bullet) is still open as goal B3.

- Presets are multipliers of `halfHourFee` (`send_controller.dart:51`: Slow =
  ½, Fast = ×2), although mempool.space returns ready-made tiers
  `fastestFee`, `halfHourFee`, `hourFee`, `economyFee`, `minimumFee` (checked).
- Inputs are signed with `sequence = 0xffffffff` (`bitcoin_signer.dart:47`),
  so RBF (BIP-125) is not signalled, and "Speed up" exists only for EVM
  (`replace_transfer.dart:194–201`). "Slow" during a fee spike can get stuck
  with no way out inside the app.

### 3.6. EVM replacement limits rest on an outdated assumption

> **Updated 2026-10-18:** fixed (goal B4 in §4). `ChainTransaction` now parses
> the four Blockscout v2 fields (old caches still read fine), the replacement
> is priced with `replacementFeeFor` = max(fast preset, original × 1.1), and
> speed-up is offered for ERC-20/approve when `raw_input` is present, reusing
> it byte for byte. The two outdated notes are gone.

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

> **Updated 2026-10-19:** fixed (goal C1 in §4): every EVM network has three nodes, and the next is tried only on a network failure.

Each EVM network has exactly one `sendRpcUrl`, all on `*.publicnode.com`. From
this machine, every request to publicnode returns a `*.o2.cz` certificate (the
local network's DNS resolves elsewhere). In that environment the wallet shows
balances (Blockscout works) but **cannot send on any EVM network**, and the
BNB balance does not load at all.

### 3.8. The PIN is weaker than "600,000 rounds" suggests

> **Updated 2026-10-19:** the password option is done (goal B6): new vaults need at least 8 characters of any kind, which changes the arithmetic below completely. The math still applies to a vault created before B6 with a 6–8 digit PIN, and unlocking never required a minimum, so those wallets keep working: changing the PIN to a password in Settings is the fix. The README now says plainly that on the web build the vault lives in browser storage, where the Keystore argument below does not hold.

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

> **Updated 2026-10-19:** the BNB sending gap (C6), the unsaved "hide balance" (D4), unnamed accounts (D3) and the three-of-six provider list (D8) are all fixed; the items below are kept as the record of what was found. One new finding: Bitcoin **testnet** addresses (`tb1…`) are derived from the same path as mainnet (`m/84'/0'/…`, coin type 0), where BIP-84 assigns testnet coin type 1. The key is the same as the mainnet key under a different prefix. It is a simplification, not a bug, and it is not changed because that would move every existing testnet address; do not reuse a testnet account as a mainnet one anyway.

- Address-poisoning checks run only on EVM (`send_screen.dart:179`) — fixed
  2026-10-18 (goal B5): the EVM-only condition is gone and `AddressGuard`
  skips the `bc1` / `tb1` bech32 prefix like it skips `0x`.
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

**A4. Scanner and paste go through `parsePaymentLink`** · 1–2 h · done 2026-10-18
The amount from the link is filled in; a link for another network offers to
switch, instead of silently replacing the network.
*Done when:* a widget test: scanning `bitcoin:…?amount=0.5` fills the amount
field with `0.5`.

**A5. EIP-681 for tokens** · half a day · done 2026-10-18
`ethereum:<token>@<id>/transfer?address=…&uint256=…` opens
`SendScreen(token: …)` with recipient and amount, if the token is in the
balance; otherwise it refuses with an explanation. Any other `/function` is
refused.
*Done when:* new cases in `payment_link_test.dart`, including "unknown token".

**A6. Polling while something is pending** · 2–3 h · done 2026-10-18
A timer in `WalletController` (EVM ~20 s, Bitcoin ~60 s) runs only while the
snapshot contains an outgoing pending transaction; it stops on lock, dispose
and network change. The price cache (60 s) already protects CoinGecko.
*Done when:* a test with a fake `ChainApi`: pending → confirmed after N ticks →
exactly one notification.

**A7. Token transfers in Activity + "Load more"** · 1–2 days · done 2026-10-19

> **As built:** `/token-transfers` is merged into the native list by hash (`mergeTokenTransfers`): "Sent ETH −fee" becomes "Sent 100 USDC" and the fee stays. `counterparty` remains the contract (a speed-up takes `to` from it); the real recipient lives in `tokenPeer`. Paging on all four chain types (Blockscout — two independent cursors, mempool.space — `last_seen`, Solana — `before`, Aptos — `start`); the cache keeps only the first page and a reload does not drop rows already loaded. An approve without a transfer reads "Token approval". The CSV gains `fee_ticker` and `note` columns.
`/token-transfers` is merged with the native list by hash: the row "Sent ETH
−fee" becomes "Sent 100 USDC", the fee stays. `ChainTransaction` gets optional
token fields (old cache still reads fine); paging via `next_page_params`; the
cache keeps only the first page. The CSV gets a separate fee-ticker column.
*Done when:* tests for the merge and for reading an old cache without the new
fields.

### Milestone B — "Safer sending" · ~4 days

**B1. Recipient check before signing** · half a day to a day · **biggest
safety gain per hour of work** · ✓ done 18.10.2026

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

**B2. Bitcoin: real fee tiers** · 1–2 h · done 2026-10-18
Slow → `hourFee`, Normal → `halfHourFee`, Fast → `fastestFee`.

**B3. Bitcoin: RBF** · signalling is one line; Speed up is 1–2 days · done 2026-10-19 (code and tests)

> **As built:** `signP2wpkh` signs with `sequence = 0xfffffffd`; `BitcoinSigner.planReplacement` is a pure BIP-125 planner (same inputs and recipients, a larger fee taken from the change, new fee ≥ old fee + size × 1 sat/vB; sub-dust change folds into the fee; honest refusals: already confirmed, foreign inputs, no RBF signal, too little change). The original is re-read (`/tx/{txid}`) right before signing: confirmed or changed means refusal. **Not confirmed live:** a 1 sat/vB transfer replaced on testnet (network access to mempool.space is blocked in the development environment).
`sequence = 0xfffffffd` in `signP2wpkh` (the BIP-143 vector sets its own
sequence values, so it stays valid). Speed up: `GET /tx/{txid}` → the same
inputs and recipient, new fee taken from change (BIP-125 rules: higher absolute
fee and a bump for the extra size); if change is not enough, refuse clearly.
*Done when:* a unit test of the replacement plan, and a transfer at 1 sat/vB
replaced and confirmed on testnet.

**B4. Honest EVM replacement (3.6)** · half a day · done 2026-10-18
Replacement price = max(fast preset, original × 1.1); speed-up for ERC-20 and
approve uses the original's `raw_input`. Remove the two outdated notes.
*Done when:* a test: replacement is always ≥ 110% of the original, and calldata
is byte-identical to `raw_input`.

**B5. Poisoning check on all networks** · 1–2 h · done 2026-10-18
`AddressGuard` skips `bc1q` / `tb1q`; remove the "EVM only" condition.

**B6. Password instead of PIN — your decision (3.8)** · a day · done 2026-10-18
The vault format does not change (the PIN is just a string for PBKDF2); only
the UI changes: `PinField`, creation, unlock, PIN change. An option, not a
requirement.

### Milestone C — "Real multi-chain" · ~2 weeks

**C1. Fallback RPC endpoints (3.7)** · half a day · done 2026-10-19

> **As built:** `sendRpcUrls` is a list of three nodes per network (PublicNode, dRPC / 1RPC or the chain's own RPC). The next node is tried only on a network error, 5xx or 429; a JSON-RPC error ends the attempt. "already known" counts as success and the hash is the keccak of the signed bytes. The same walk covers nonce, fee data, estimateGas, receipt and eth_call.
`sendRpcUrl` → a list. Move to the next node only on a network error, not on a
JSON-RPC error. "already known" on a repeated `eth_sendRawTransaction` counts as
success: identical signed bytes produce the same hash.
*Done when:* a test: the first node fails, the second accepts, and the hash is
the same.

**C2. Portfolio screen across all networks** · 1–2 days · done 2026-10-19

> **As built:** `PortfolioController` + `PortfolioScreen` (a "Portfolio" card on the home screen): one price request for all coins (`PriceApi.fetchPrices`), balances and tokens in parallel, sorted by value, a tap switches network. A network that cannot be read shows as unavailable, not as empty, and the total is then marked as possibly too low.
One price request for all coins (`ids=bitcoin,ethereum,…` — checked), balances
in parallel, tokens; the list sorted by value, tap to switch network. Replaces
"check ten networks to see the total".

**C3. SPL tokens (roadmap)** · a day · done 2026-10-19

> **As built:** `getTokenAccountsByOwner` (jsonParsed) for Token and Token-2022, accounts of one mint merged. The chain knows neither ticker nor price: prices come from one `simple/token_price/solana` request, the ticker from `coins/solana/contract/{mint}` (cached, ≤ 5 lookups per call). An unknown token keeps a shortened-mint label and has no price. Tokens are **shown but not sent** (tap and "Approvals" are EVM-only).
`getTokenAccountsByOwner` (jsonParsed, Token and Token-2022 programs) →
`TokenBalance`.

**C4. Sending SOL (roadmap)** · 3–5 days · done 2026-10-19 (code, vector, tests)

> **As built:** `SolanaSigner` (legacy message + ed25519). **External vector:** the message and the signed transaction match `solders` (the Rust solana-sdk) byte for byte. Before signing: a fresh blockhash, `getFeeForMessage`, both balances, the rent minimum. Rules: a new recipient must receive at least the minimum; the sender's remainder is 0 or at least the minimum. Solana Devnet is in the catalog; `tool/verify_solana.dart` runs `simulateTransaction` with `sigVerify`. **Not run:** that script (network access to devnet is blocked in the development environment).
Legacy message (header, compact-u16, `getLatestBlockhash`, System Program
transfer instruction), ed25519 — `ed25519_edwards` is already a dependency,
`sendTransaction`, `getSignatureStatuses`. Pitfall: a new recipient account must
receive at least the rent-exempt minimum (890,880 lamports ≈ 0.00089 SOL), and
the sender's remaining balance must not fall between zero and that minimum.
Add Solana devnet for verification.
*Done when:* a serialisation test vector + `simulateTransaction` with
`sigVerify` on devnet — the equivalent of `verify_eip1559.dart`.

**C5. Sending APT (roadmap)** · 3–4 days · done 2026-10-19 (code, vector, tests)

> **As built:** `AptosSigner` (BCS `RawTransaction`, `sha3_256("APTOS::RawTransaction") ‖ bcs`, ed25519 authenticator). **External vector:** matches the official `aptos-sdk` byte for byte. Before signing: sequence number, chain id and time from the ledger (not the phone clock), gas price, and a **dry run through `/transactions/simulate`** with a zero signature; `max_gas = max(2 × gas_used, 2000)`. `tool/verify_aptos.dart` simulates on testnet. **Not run:** that script.
BCS `RawTransaction` (sequence_number from `/accounts/{a}`,
`0x1::aptos_account::transfer`, gas, expiration, chain_id); the message to sign
= `sha3_256("APTOS::RawTransaction") ‖ bcs`; POST `/transactions` as
`application/x.aptos.signed_transaction+bcs`. Start with
`/transactions/simulate`.
*Done when:* a BCS test vector + a successful simulation on testnet.

**C6. Sending BNB** · 2 h + verification · done 2026-10-19 (live check not run)

> **As built:** BNB has `sendRpcUrls`, so `canSign`. The Send screen says there is no history: no speed-up/cancel, no notifications and no history-based poisoning check (`NetworkConfig.hasHistory`). `tool/verify_eip1559.dart [sepolia|bsc-testnet|bnb]` is parameterised. **Run `bsc-testnet` before real funds** — type-2 transactions on BSC were not checked from this environment.
`sendRpcUrl` + `verify_eip1559.dart`, parameterised for BSC testnet (chainId
97). Without history there will be no speed-up, no notifications and no
history-based poisoning check on this network — the UI must say so.

### Milestone D — "Convenience" · each goal at most a day

| goal | effort | note |
|---|---|---|
| D1. Payment request: amount in Receive → QR with BIP-21 / EIP-681 / Solana Pay / `aptos:` + Share | half a day | `share_plus` is already there; round-trip test through `parsePaymentLink` · done 2026-10-19 |
| D2. Fiat amount in Send | half a day | after A1; the amount is signed in coins, shown on review · done 2026-10-19 |
| D3. Account names | 2–3 h | `shared_preferences`, account picker in Settings · done 2026-10-19 |
| D4. Privacy mode that persists and applies everywhere | 2 h | `_hideBalance` → `SettingsController` · done 2026-10-19 |
| D5. Local notes on transactions, included in CSV | half a day | hash → text map · done 2026-10-19 |
| D6. ENS (`name.eth`) in the recipient field | a day | eth_call to the Universal Resolver; the resolved address is shown on review and passes B1 · done 2026-10-19 |
| D7. Search in Activity by address, label or hash | 2–3 h | after A7 · done 2026-10-19 |
| D8. Full provider list in About | 10 min | see 3.9 · done 2026-10-18 |

### Milestone E — "Trust what is already built" · done 2026-10-19

Goals that came out of the review of A–D rather than from the original analysis.

| goal | status | note |
|---|---|---|
| E1. CI | done | `.github/workflows/ci.yml`: `flutter analyze` and `flutter test` on every push to `main` and every PR, Flutter pinned to the version in the README. |
| E2. Run the live checks | done except two | See §8. The run found a real bug (the Aptos gas floor). |
| E3. Live checks that fail loudly | done | Every `tool/verify_*.dart` now sets a non-zero exit code on `FAIL`, so a workflow cannot go green on a failed check; `.github/workflows/live-checks.yml` runs them by hand. `tool/verify_ens.dart` is new. |
| E4. Derivation vectors beyond the pinned ones | done | The official SLIP-0010 ed25519 vectors (`test/slip10_vectors_test.dart`) pin the derivation function for any path; Bitcoin accounts 1–2, the testnet prefix and EVM accounts 1–2 are pinned with values from an independent BIP-32 implementation that reproduces the published account-0 vectors. Both are in `test/`. |
| E5. Manual "hide token" | done | Long-press a token on the home list; "Show N hidden" restores it; stored per network and contract. The one known limit (the totals still counted a priced hidden token) was removed by F1. |

### Milestone F — "Beyond one seed" · done 2026-10-19 (code, tests and Android builds; device checks open)

Five items that were listed here as larger ideas, plus the one known limit left from E5. The code is covered by tests and the Android app builds in debug and release; the two features that depend on a real phone are **not exercised on hardware** (§8).

**F1. Hidden tokens leave the totals** · done
`PortfolioEntry.visibleTokens` and `WalletController.hiddenTokens` drop a hidden token from `portfolioFiat` and from the Portfolio screen's total and token count, and hiding or showing a token recomputes the total at once. The token stays in the snapshot and in the CSV: hiding is about what the wallet shows and adds up, not about what is on-chain. The `ponytail:` marker of E5 became a doc comment. *Done when:* a test: $5 ETH + $1000 USDC + $500 priced airdrop, airdrop hidden → $1005, shown again → back.

**F2. Several recovery phrases** · done

> **As built:** one vault, one password, one unlock. The vault payload stays `{"m","p"}` for the first wallet and adds `i` (its id, when it is not `main`) and `x` (the other phrases, each `{i, m, p}`); a vault with one wallet serialises exactly as before and every older vault, including the bare-mnemonic v1, still opens. Adding or removing a phrase checks the password first and re-encrypts the whole vault; a duplicate (same phrase and passphrase) is refused, the last phrase cannot be removed one by one (erasing is its own action). Names, the active wallet and the watch-only wallets live in a non-secret book (`nova.wallet.book`); each wallet has its own account index and count (the first keeps the original keys, so existing installs read their old values), and account names are scoped `walletId:index`. Wallet ids are time-based and never reused. Switching derives the new seed first and swaps it in one step, so no caller sees the new id with the old seed. Changing the password re-encrypts every phrase. UI: Settings → Wallets (switch, rename, remove, add); the create/import flows end in the usual "set a password" step on a fresh device and in "confirm your password" when a vault already exists.

*Done when:* tests for adding, wrong password leaving the vault untouched, duplicates, per-wallet accounts, password change, removal (including promoting the next phrase), and opening a pre-F vault.

**F3. Watch-only wallets** · done

> **As built:** a wallet holds at most one address per family (`btc`, `btc-test`, `evm`, `sol`, `apt`), recognised from the pasted or scanned address (`WatchAddresses.detect`, payment links are unwrapped). The one ambiguity: an Aptos address of exactly 40 hex digits reads as EVM. A watch-only wallet needs no vault: a device with only watch-only wallets opens straight onto them, `lock()` does nothing, and the password, fingerprint and auto-lock settings are hidden; adding a phrase later creates the vault and asks for a password then. Erasing the recovery phrases leaves watch-only wallets in place. **Signing is refused in layers:** `canSign` is false (no seed in memory), the Send screen shows an explanation instead of the form, every `SendController` entry point refuses before touching the network, and Speed up / Cancel / Revoke are hidden and guarded. A network the wallet follows no address on shows "Nothing followed here" rather than an empty balance. The foreground confirmation watcher ignores a followed address (its outgoing transfers are not ones the user is waiting on).

*Done when:* tests for opening without a password, surviving a restart, sitting next to a seed wallet, refusing to send, and detecting every address family and rejecting a bad checksum.

**F4. Fingerprint bound to the hardware** · done (compiled; not run on a device)

> **As built:** `BoundSecret.kt` keeps the password under an AES-256-GCM Keystore key created with `setUserAuthenticationRequired(true)` and **no validity window** (timeout 0 on API 30+, per-use before), `BIOMETRIC_STRONG` only, `setInvalidatedByBiometricEnrollment(true)`, and every encrypt/decrypt goes through a `BiometricPrompt` `CryptoObject`. Each write makes a fresh key. The Dart `SecurePinStore` therefore turns a read into proof that a finger was presented: `unlockWithBiometrics` and `confirmWithBiometrics` are one prompt, with no separate "did the dialog pass" flag to skip. A non-secret preference marks that a secret exists, so the lock screen does not prompt just to find out. If the fingerprints change the key is dead: the feature switches itself off and the lock screen says why. Changing the password needs one fingerprint to update the stored copy; cancelling drops the stale copy and turns the feature off rather than leave an old password replayable. The unbound copy older versions kept in `flutter_secure_storage` is deleted at launch (users enable the feature once more). `local_auth` was removed. The web build has no fingerprint unlock.

*Done when:* tests of the Dart half against a scripted channel (supported, write, cancel, invalidated, clear) and of the controller (single prompt, reset notice, stale copy dropped, password change); the Kotlin compiles into debug and release APKs. **Not done:** a run on a phone — see §8.

**F5. Notifications while closed** · done (logic tested; scheduling not run on a device)

> **As built:** an opt-in WorkManager periodic job (15 minutes is the platform minimum; network required), Android only. `BackgroundChecker` is plain Dart: for every stored `BackgroundTarget` (an address and its network — public data written while the wallet was unlocked; watch-only addresses always) it reads the first activity page and (a) announces a watched outgoing transfer that has confirmed, removing it from the same persisted set the foreground watcher uses so only one of them speaks, and (b) announces a new incoming transfer. The first look at an address only learns its history, so turning the feature on does not replay old transfers; a failed node changes nothing and is retried next pass; at most 120 hashes are remembered per address. A native receipt counts when positive; a token counts only if the user already held it at the last snapshot and did not hide it, so an unsolicited airdrop does not ping the phone. Privacy mode keeps the amount out of the text; with several wallets the wallet's name is added. There is no seed, password or signing in the background. Settings → "Notify when closed" asks for the notification permission when needed.

*Done when:* tests for first look vs later arrivals, once-only announcement, privacy mode, failed/zero rows, unreachable node, shared addresses, wallet names, token rules, confirmation of a watched transfer, and the target list following wallets in and out; the app builds with the plugin.

### Larger ideas — separate branches

- **Sending SPL tokens and Aptos fungible assets** — balances are shown today. SPL needs the recipient's associated token account (created on demand, with its own rent) and a new vector from an external implementation, plus a devnet simulation, before it may sign (§7 rule 3).
- **Ukrainian localisation** — all strings are currently English in code;
  2–3 days of mechanical ARB work.

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
Rows 1–4 and all of row 5 except B3 (Bitcoin RBF) are done as of 2026-10-18. Rows 6–10 (A7, C1, D1, B3 Speed up, C2, C3 → C6, D2–D7) were done on 2026-10-19: everything is in code and tests. The live checks in §8 were run the same day; two of them still need a funded testnet wallet. Milestone F (F1–F5) was added and built on the same day; its two phone-dependent items still need a device.

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
- **Own push server** — breaks "no backend". (F5 does not need one: the phone polls public data itself, at the cost of up to ~15 minutes of delay.)

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
8. **Anything that can sign goes through the active wallet's `canSign`.** A
   watch-only wallet has no seed in memory, and every send entry point says so
   before it touches the network.
9. **A secret kept for convenience is bound to the hardware, not to a flag.**
   The fingerprint-unlock password lives behind a Keystore key that needs the
   finger for every use; do not add another way to read it.
10. **The background worker never holds a secret.** It reads public data for
    addresses the app stored while unlocked, and nothing there can sign.

---

## 8. Live checks

Outbound traffic to chain nodes was blocked while the code of §4 was written, so the paths below had only vectors behind them. On 2026-10-19 the no-spend checks were run from a machine with network access. None of them signs with a funded key or spends anything.

| What | How | Result |
|---|---|---|
| EVM on Sepolia | `dart run tool/verify_eip1559.dart sepolia` | **PASS** — the node decoded the type-2 transaction and rejected it only for insufficient funds |
| BNB Chain | `dart run tool/verify_eip1559.dart bsc-testnet` | **PASS** — same, on chain id 97 |
| Solana | `dart run tool/verify_solana.dart` | **PASS** — `AccountNotFound` for the real signature, `SignatureFailure` for the tampered one |
| Aptos | `dart run tool/verify_aptos.dart` | **PASS after a fix** — see below |
| ENS | `dart run tool/verify_ens.dart` | **PASS** — `vitalik.eth` resolved to `0xd8da…6045`; an unregistered name reverted and is treated as "nothing" |
| Fallback RPC | block the first node (or point it at a dead host) | **not run live** — covered by `test/rpc_failover_test.dart` with a fake transport; a real dead node has not been tried |
| Bitcoin RBF | send 1 sat/vB on testnet → "Speed up" → confirmation | **not run** — needs a funded testnet wallet; the replacement planner is covered by `test/bitcoin_rbf_test.dart` |

**What the Aptos run found.** The first run failed: the node parsed the BCS transaction but refused it with `MAX_GAS_UNITS_BELOW_MIN_TRANSACTION_GAS_UNITS`. The wallet's `max_gas_amount` floor was 2 000 units; bisecting against the testnet node put the intrinsic minimum at **5 210**. Every real Aptos send would have been rejected, and no vector or unit test could have shown it, because the minimum is a property of the chain. The floor is now 10 000 (`AptosSigner.maxGasFloor`); only gas actually used is charged. **Mainnet was not probed**, so that margin is a judgement, not a measurement: run `verify_aptos.dart` against mainnet's node before relying on it. With the floor fixed, a made-up sender fails earlier (`INVALID_AUTH_KEY`), so the tool now derives the sender from the key and accepts `INSUFFICIENT_BALANCE_FOR_TRANSACTION_FEE` as proof the node accepted the transaction.

The same checks can be run from GitHub: **Actions → Live checks → Run workflow**.

**Milestone F (checked from the development environment, no phone):**

| What | How | Result |
|---|---|---|
| Android app builds | `flutter build apk --debug` and `--release` (R8) with the new Kotlin and the WorkManager plugin | **PASS** — both APKs build; the release dex contains the bound-secret channel and alias; the manifest carries `USE_BIOMETRIC`, `POST_NOTIFICATIONS`, WorkManager's permissions |
| Web build | `flutter build web --release` | **PASS** — the web build compiles; it has no fingerprint unlock and no background job |
| Fingerprint-bound key | enable fingerprint unlock, lock, unlock with the finger; add a finger in system settings and try again; change the password | **not run** — needs a phone with an enrolled fingerprint; the Dart side is tested against a scripted channel, the Kotlin only compiles |
| Background job | turn on "Notify when closed", close the app, receive a testnet transfer | **not run** — needs a phone; `BackgroundChecker` is tested with a fake chain, scheduling and delivery are not |
| Upgrade from 0.4.0 | open a 0.4.0 install with a wallet | **not run on a device** — covered by a test that opens a vault written by the old format and by the unchanged storage keys of the first wallet |

The WorkManager plugin currently prints a warning at build time that it applies the Kotlin Gradle Plugin itself; it is harmless today and will need a plugin update before a future Flutter release stops allowing it.

Still worth doing before real funds: a Bitcoin testnet speed-up, one send of a few cents on each network the wallet signs, and the two phone checks above.
