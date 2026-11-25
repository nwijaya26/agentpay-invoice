# Aevum Starter Kit

Everything you need to build and demo a stablecoin app on **QDay Aevum testnet** (chain `44005`):

- **Contracts (Foundry):** `Checkout.sol`, a minimal pay-per-order contract with two payment modes, plus tests that run against the real tUSD8 on a local fork.
- **Web app (Next.js):** a setup checker, a checkout with standard and gasless payments, on-chain receipts and an activity feed. Connect with MetaMask, Rabby, any browser wallet, or WalletConnect.
- **TypeScript examples:** sign and relay a gasless payment, read events past the 1,000-block log limit, and check a wallet's setup.
- **`@aevum-kit/aevum`:** chain config, ABIs and helpers shared by all of the above. Import it in your own code.

Fork it, rename `Checkout` into whatever you're building (an invoice, a ticket, payroll, a pledge), and keep the plumbing.

> **Judging counts activity on Aevum.** Contracts, payments and transfers must happen on Aevum testnet. Settling only on another chain (for example x402 on Base) doesn't count.

---

## AgentPay Invoice — live deployment (Aevum Builder Challenge #1)

This repo is the **AgentPay Invoice** submission: a tUSD8 invoice cashier with the
amount locked in on chain (`InvoiceCheckout`), a Confirmation-of-Payee registry
(`PayeeRegistry`), and a budget-controlled agent wallet (`AgentWallet`: per-period
budget cap, session expiry, payee allowlist, instant revoke). An agent pays invoices
gaslessly via EIP-3009 (`payWithAuthorization`, nonce bound to payer + invoice).
Built on the Aevum Starter Kit (MIT, PQA Labs).

**Deployed on Aevum testnet (chain 44005), 22 Nov 2026**, by
`0x29EEbb597abab8208dDf9Af845E11FcceBC44948` from commit
`93289ae321ab80c004141059f3b658b43ddb3184`. (The explorer's contract-verification
feature is not live yet, so the addresses + this exact commit are the reference.)

| Contract | Address | Deploy tx |
|---|---|---|
| InvoiceCheckout | [`0x1eeE2A5CeBe0CF61A042cEBbE649c8eE31b5F6A2`](https://explorer-test.qday.info/address/0x1eeE2A5CeBe0CF61A042cEBbE649c8eE31b5F6A2) | [`0x672cd657…2026369f`](https://explorer-test.qday.info/tx/0x672cd65791ccf0885961c1354922f962866268aaf4bd6097083d894b2026369f) |
| PayeeRegistry | [`0x7424F543673488C1aD319Af1EedE639AB50Fa52b`](https://explorer-test.qday.info/address/0x7424F543673488C1aD319Af1EedE639AB50Fa52b) | [`0xb8b6f0a9…f15eafa4`](https://explorer-test.qday.info/tx/0xb8b6f0a9a4c5498e45cf9da7e4e444333847b39e23b91e3ec839d841f15eafa4) |
| AgentWallet | [`0x9C80e633937D1e61d40a43709f9c5a5E47A957b9`](https://explorer-test.qday.info/address/0x9C80e633937D1e61d40a43709f9c5a5E47A957b9) | [`0x958dc35a…f063f`](https://explorer-test.qday.info/tx/0x958dc35a220e0d4bd6c8d95c5d5946963ec7abadb09e5987213cdc0b643f063f) |
| Checkout (starter kit) | [`0x71f6bC3F9854900095d9A469911f2962DA88168F`](https://explorer-test.qday.info/address/0x71f6bC3F9854900095d9A469911f2962DA88168F) | [`0x52681374…223a5dcc`](https://explorer-test.qday.info/tx/0x52681374d8aef6adc4efe470b88b7cdf36e4a07dfc675033aa40b5fa223a5dcc) |

**Proof transactions (22 Nov 2026)** — payee `agentpay-merchant` registered in the
registry, resolving to `0x482EC60cAF715E7Bd06Ddd1176AEa7855697A758`:

- Register payee: [`0xa696c717…bf3d2b71`](https://explorer-test.qday.info/tx/0xa696c71797fe400f20bb34a19ab9a37ab2e690b7afd98324452e08f8bf3d2b71)
- Invoice #1 (1 tUSD8, id `0x8a5779f7…d50135c9`): [create](https://explorer-test.qday.info/tx/0xf5913e747635d0bd4b29d4961187fa67281a9977986dce6e76385fe85b5f4abb) → [pay (standard)](https://explorer-test.qday.info/tx/0xb2c31b4c2da2d98a6ba8c25cda0e7b51858351de22eb183abdd27347c3a1971c) → status **Paid**
- Invoice #2 (1 tUSD8, id `0x6d8c2950…a3dc7f7`): [create](https://explorer-test.qday.info/tx/0x0eb9788c8794427f658c0c10ac0066016df0252c7fea7d1f3a11571c8885af39) → [payWithAuthorization (gasless EIP-3009)](https://explorer-test.qday.info/tx/0x5cd4351e58eb2564a4d23de2ba48fde055cf4a31b95ba575dc44fb8d855d132e) → status **Paid**

### Proof scenarios #4–#5 — ✅ proven on-chain (25 Nov 2026)

Session: budget cap 1,000,000 base units (1 tUSD8), period 604800 s (7 days), agent = owner = burner, payee `agentpay-merchant` allowlisted. All receipts verified via `cast receipt` + `cast call` on chain 44005.

- **#4 — Over-budget payment reverts:** [configure session](https://explorer-test.qday.info/tx/0x3cad38c31779eb127bc89fed708d6ed337a5c4e21e27d0acf8dde66cfec2608c) (block 4057235) → [pay 500,000 — success](https://explorer-test.qday.info/tx/0x47d049d2cbb14ab010377122e4e21c7ee79bd59950b0a808075894497186a30a) (block 4057265, spent 500,000, remaining 500,000) → [pay 600,000 — **REVERT, receipt status 0x0**](https://explorer-test.qday.info/tx/0xd0d023d5584a9a6024140f44f647a8c9b55a428762800b14a0213048d5a5f576) (block 4057287; simulated first: `BudgetExceeded(500000, 600000)`). State after: spent still 500,000, balances unchanged.
- **#5 — Payment after revoke reverts:** [revoke](https://explorer-test.qday.info/tx/0x2e27e6dd6b238cda4814398c156e0fee4b02631452897170f5a54b3b9945e785) (block 4057310, `sessionActive` → false) → [pay 100,000 — **REVERT, receipt status 0x0**](https://explorer-test.qday.info/tx/0x53abbfa6143afd3ca3d26c58d855ceef03ba295b0696bebd3d66314b8aae5352) (block 4057326; simulated first: `SessionRevokedError`). Final state: `revoked` = true, `sessionActive` = false, spent 500,000, wallet 0 tUSD8, payee 3.0 tUSD8.
- Note: the scenario ran in two cycles — in cycle 1 `cast send` refused to broadcast the reverting calls at gas estimation (the RPC itself returned the exact revert data, so no receipt was mined); cycle 2 repeated the scenario with identical parameters and an explicit `--gas-limit 150000`, mining both 0x0 receipts above. Full step log: `scenarios-4-5-results.json` in the repo root (25 Nov 2026).
- **Live demo URL:** https://agentpay-invoice.vercel.app (Vercel, `aevum`-only mode, public — no login needed).

---

## AgentPay Invoice — problem, architecture, workflow

### Problem statement

An autonomous agent that pays real invoices needs money movement with guardrails,
not a blank cheque. Three things go wrong with a plain checkout:

1. **The amount is not locked in.** The starter kit's `Checkout` lets anyone pay any
   order with any amount — `pay(orderId, 1)` marks an order paid for 0.000001 tUSD8.
   A merchant cannot trust `isPaid` alone.
2. **The payee is not verified.** Nothing checks that the address on an invoice is
   really the merchant it claims to be.
3. **The agent is unconstrained.** A wallet that an agent controls can drain
   everything, to anyone, at any time — no budget, no expiry, no allowlist, no
   off-switch.

AgentPay Invoice fixes all three on chain: the invoice amount is locked at
creation (`InvoiceCheckout`), the payee name is verified before payment
(`PayeeRegistry`, Confirmation-of-Payee), and the agent spends only inside a
budgeted, expiring, allowlisted session the owner can revoke instantly
(`AgentWallet`). The agent itself never needs gas: it signs an EIP-3009
authorization and a relayer submits it (`payWithAuthorization`).

### Architecture

```mermaid
flowchart LR
    Merchant["Merchant\n(createInvoice)"] --> IC["InvoiceCheckout\n0x1eeE…5F6A2"]
    Registry["PayeeRegistry\n0x7424…a52b\nregister / resolve / verify"] --> Agent["Agent script\npay-invoice-agent.ts"]
    Agent -->|1. verify name → address| Registry
    Agent -->|2. check session, allowlist,\nremaining budget| AW["AgentWallet\n0x9C80…57b9\nconfigureSession / revoke\nsetPayeeAllowed / payInvoice"]
    Agent -->|3. sign EIP-3009\nReceiveWithAuthorization\nnonce = keccak256(payer, invoiceId)| IC
    Relayer["Relayer\n(submits tx, pays gas)"] -->|payWithAuthorization| IC
    AW -->|payInvoice: forceApprove exact amount\nthen checkout.pay| IC
    IC -->|transferFrom / safeTransfer| Payee["Payee\ntUSD8 0x4565…483"]
    IC -->|Paid event = on-chain receipt| Explorer["Explorer\n explorer-test.qday.info"]
```

Contract roles (source: `contracts/src/`):

| Contract | What it does | Key functions |
|---|---|---|
| `InvoiceCheckout` | Invoice with the amount locked in at creation; per-invoice token, deadline, cancel/refund; money goes straight to the payee, nothing is escrowed. | `createInvoice`, `pay`, `payWithAuthorization`, `cancelInvoice`, `refundInvoice`, `authorizationNonce`, `statusOf`, `isPaid` |
| `PayeeRegistry` | Confirmation-of-Payee: name → address mapping. Names are case-sensitive (`keccak256` of the exact string); whoever registers a name first controls it. | `register`, `update`, `remove`, `resolve`, `verify`, `isRegistered` |
| `AgentWallet` | Budget-controlled agent wallet (OZ `Ownable`). Per-period budget cap with automatic rollover, session expiry, payee allowlist, instant revoke. | `configureSession`, `revoke`, `setPayeeAllowed`, `fund`, `withdraw`, `pay`, `payInvoice`, `remainingBudget`, `sessionActive` |
| `Checkout` (starter kit) | The kit's minimal pay-per-order contract, deployed unchanged for reference. | `pay`, `payWithAuthorization` |

### Core workflow, step by step

1. **Merchant registers a name** — `PayeeRegistry.register("agentpay-merchant", <payee address>)`.
   Live: [`0xa696c717…bf3d2b71`](https://explorer-test.qday.info/tx/0xa696c71797fe400f20bb34a19ab9a37ab2e690b7afd98324452e08f8bf3d2b71).
2. **Merchant creates an invoice** — `InvoiceCheckout.createInvoice(invoiceId, payee, token, amount, deadline, ref)`.
   The amount is now locked: any payment with a different amount reverts with `WrongAmount(expected, actual)`.
3. **Agent verifies the payee** — `PayeeRegistry.verify("agentpay-merchant", invoice.payee)` must be `true`
   before any money moves; the agent script (`examples/src/pay-invoice-agent.ts`) refuses to pay otherwise.
4. **Agent checks its session** — `AgentWallet.sessionActive()`, the payee in `allowedPayee`, and
   `remainingBudget()` covering the invoice amount. Over budget reverts with `BudgetExceeded`; a
   non-allowlisted payee with `PayeeNotAllowed`; an expired session with `SessionExpired`; a revoked
   session with `SessionRevokedError`.
5. **Agent pays, gaslessly** — the agent signs an EIP-3009 `ReceiveWithAuthorization` (tUSD8 domain
   `name: "tUSD8"`, `version: "2"`, nonce `authorizationNonce(payer, invoiceId) =
   keccak256(payer, invoiceId)`), and a relayer submits `InvoiceCheckout.payWithAuthorization(...)`.
   Live: [`0x5cd4351e…d132e`](https://explorer-test.qday.info/tx/0x5cd4351e58eb2564a4d23de2ba48fde055cf4a31b95ba575dc44fb8d855d132e).
   Standard payment (approve + `pay`) also works — live: [`0xb2c31b4c…1971c`](https://explorer-test.qday.info/tx/0xb2c31b4c2da2d98a6ba8c25cda0e7b51858351de22eb183abdd27347c3a1971c).
   Alternatively the wallet itself pays via `AgentWallet.payInvoice(checkout, invoiceId)`, which
   approves the checkout for exactly the invoice amount (remaining allowance 0 afterwards).
6. **Receipt** — the `Paid(invoiceId, payer, payee, amount)` event is the on-chain receipt;
   `statusOf(invoiceId)` reads `2` (`Paid`). Status values: `0 None, 1 Open, 2 Paid, 3 Cancelled, 4 Refunded`.

### Technology

- **Chain:** QDay Aevum testnet, chain `44005`, EVM **Shanghai** (`evm_version = "shanghai"`,
  solc `0.8.24` — see `contracts/foundry.toml`; do not change it, Cancun bytecode reverts with `invalid opcode`).
- **Token:** tUSD8 `0x456569838f1d43009A91ebA4263147Afd7233483`, 6 decimals, EIP-2612 `permit` +
  EIP-3009 signed transfers, EIP-712 domain `name: "tUSD8"`, `version: "2"`.
- **Contracts:** Solidity `^0.8.24`, Foundry `1.10.0`, OpenZeppelin (`Ownable`, `SafeERC20`).
  Tests: `67/67` unit + `7/7` fork against the real tUSD8 (`make check`).
- **Agent script / examples:** TypeScript + viem (`examples/src/pay-invoice-agent.ts`,
  pattern from the kit's `examples/pay-gasless.ts`).
- **Web:** Next.js + wagmi + RainbowKit, `@aevum-kit/aevum` (chain config, ABIs, EIP-3009 typed data, `getLogsChunked`).
- **Transactions:** legacy (type 0) on testnet; RPC over HTTPS only, no WebSocket; `eth_getLogs` in
  max 1,000-block chunks.

---

## Environment variables

No `.env` file is committed, and none is needed to build or test. Copy the
`.env.example` file next to the part you run and fill in only the values you need.
Never commit a filled-in `.env`, and never put a private key in a file that is
tracked by git. There is no root `.env.example` and no `contracts/.env.example`;
deploy-time variables are passed on the command line (see below).

### `examples/.env.example` → `examples/.env`

| Variable | Required? | Example (non-secret) | Used by / for |
|---|---|---|---|
| `RPC_URL` | No (default Aevum testnet) | `https://rpc-test.qday.info` | All example scripts. `http://127.0.0.1:8555` for `make fork`, `http://127.0.0.1:8545` for `make anvil`. |
| `CHECKOUT_ADDRESS` | For kit examples | `0x71f6bC3F9854900095d9A469911f2962DA88168F` | `check-setup`, `pay-gasless`, `read-payments` (kit `Checkout`). |
| `ADDRESS` | No | `0x29EEbb597abab8208dDf9Af845E11FcceBC44948` | `check-setup` (address to inspect); `read-payments` (filter by payer). |
| `BUYER_KEY` | For `pay-gasless` | *(test wallet key — never commit)* | `pay-gasless`: signs the EIP-3009 authorization (needs tUSD8, no gas). |
| `RELAYER_KEY` | For gasless scripts | *(test wallet key — never commit)* | `pay-gasless`, `pay-invoice-agent`: submits the transaction and pays the gas (needs a little tQDAY). |
| `INVOICE_CHECKOUT_ADDRESS` | For `pay-invoice-agent` | `0x1eeE2A5CeBe0CF61A042cEBbE649c8eE31b5F6A2` | `pay-invoice-agent`: the `InvoiceCheckout` to pay. |
| `PAYEE_REGISTRY_ADDRESS` | For `pay-invoice-agent` | `0x7424F543673488C1aD319Af1EedE639AB50Fa52b` | `pay-invoice-agent`: the `PayeeRegistry` for the Confirmation-of-Payee check. |
| `AGENT_WALLET_ADDRESS` | Optional for `pay-invoice-agent` | `0x9C80e633937D1e61d40a43709f9c5a5E47A957b9` | `pay-invoice-agent`: if set, the agent's session, allowlist and remaining budget are checked before paying. |
| `INVOICE_ID` | For `pay-invoice-agent` | `0x6d8c295035c1a1e8cc8f251fe07da7674403dc2a67257ec6850d03ed8a3dc7f7` | `pay-invoice-agent`: 32-byte hex id of the invoice to pay. |
| `PAYEE_NAME` | For `pay-invoice-agent` | `agentpay-merchant` | `pay-invoice-agent`: name to verify in the registry. |
| `AGENT_KEY` | For `pay-invoice-agent` | *(test wallet key — never commit)* | `pay-invoice-agent`: signs the EIP-3009 authorization (needs tUSD8, no gas). |

### `web/.env.example` → `web/.env.local`

| Variable | Required? | Example (non-secret) | Used by / for |
|---|---|---|---|
| `NEXT_PUBLIC_NETWORKS` | No (default `aevum`) | `aevum` (live) or `fork,aevum` (local dev) | Which networks the web app offers. Keep it to `aevum` online. |
| `NEXT_PUBLIC_CHECKOUT_AEVUM` | For live web | `0x71f6bC3F9854900095d9A469911f2962DA88168F` | Kit `Checkout` address on Aevum testnet. |
| `NEXT_PUBLIC_CHECKOUT_FORK` | For local fork | *(address printed by `make deploy-fork`)* | Kit `Checkout` address on the local fork. |
| `NEXT_PUBLIC_CHECKOUT_LOCAL` | For local anvil | *(address printed by `make deploy-local`)* | Kit `Checkout` address on local anvil. |
| `NEXT_PUBLIC_DEPLOY_BLOCK_AEVUM` | No | *(block number of your deploy)* | Activity page: start scanning events from this block. |
| `NEXT_PUBLIC_DEPLOY_BLOCK_FORK` | No | *(block number of your fork deploy)* | Same, for the fork. |
| `NEXT_PUBLIC_WC_PROJECT_ID` | No | *(free at cloud.reown.com)* | Enables WalletConnect (mobile wallets). |
| `NEXT_PUBLIC_REPO_URL` | No | *(your repo URL)* | Docs page "Source" link. |
| `RELAYER_PRIVATE_KEY` | No (enables gasless) | *(fresh test wallet key — never commit; mark Sensitive on Vercel)* | Server-side relayer: submits signed payments and pays the gas. Refuses anvil's public keys on Aevum testnet. |
| `RELAYER_DAILY_TX_LIMIT` | No (default `500`) | `500` | Max transactions the relayer sends per day (per server process). |
| `TRUSTED_IP_HEADER` | No | `x-vercel-forwarded-for` (Vercel) / `cf-connecting-ip` (Cloudflare) | Real client-IP header for the relayer's rate limit. |

### Deploy-time variables (command line, not files)

| Variable | Required? | Example | Used by / for |
|---|---|---|---|
| `ACCOUNT` | Yes, for `make deploy-aevum` | `aevum-deployer` | Keystore name created with `cast wallet import <name> --interactive`. Never paste a key into a file or shell history. |
| `MERCHANT` | No (defaults to deployer) | `0x482EC60cAF715E7Bd06Ddd1176AEa7855697A758` | `make deploy-aevum` / `make deploy-fork`: receives kit `Checkout` payments. |
| `OWNER` | No (defaults to deployer) | `0x29EEbb597abab8208dDf9Af845E11FcceBC44948` | `make deploy-aevum` / `make deploy-fork`: owns the deployed `AgentWallet`. |
| `TO` | Yes, for `make deal` / `make mint` | *(your wallet address)* | `make deal`: fork-only, gives tUSD8 + 10 tQDAY. `make mint`: anvil-only, mints MockUSD8. |
| `AMOUNT` | No (default `100`) | `10` | `make deal` / `make mint`: amount of tokens. |
| `CHECKOUT` | Yes, for `make mint` | *(address from `make deploy-local`)* | `make mint`: the `Checkout` whose token is minted. |
| `INVOICE_CHECKOUT` | Yes, for `make smoke-fork` | *(address from `make deploy-fork`)* | `make smoke-fork`: post-deploy smoke test (create invoice → pay exact → Paid) on the fork. |

---

## Reproduce from scratch (turnkey)

Everything below was run against the exact deployed commit
`93289ae321ab80c004141059f3b658b43ddb3184` (repo HEAD at time of writing: `fb2f76c`).
No funds are needed for the local steps — the fork copies Aevum's real state and
`make deal` gives you virtual test balances.

> **Public repo URL: https://github.com/nwijaya26/agentpay-invoice.** The code
> is public on GitHub (`nwijaya26`). If you work from the starter-kit
> baseline instead (`https://github.com/qday-io/aevum-starter-kit.git`, baseline `e87bcff`),
> apply the AgentPay commits on top. Every command below is the same either way.

### Prerequisites

- [Node 22+](https://nodejs.org), [pnpm](https://pnpm.io/installation),
  [Foundry](https://book.getfoundry.sh/getting-started/installation) (`foundryup`).
  Verified versions used for this build: Foundry `1.10.0`, pnpm `12.21.0`, Node `v24.22.1`.
- Git (with submodules — the repo vendors `forge-std` and `openzeppelin-contracts`).

### 1. Clone and install

```bash
git clone --recursive https://github.com/nwijaya26/agentpay-invoice.git
cd agentpay-invoice
make install          # Solidity libs + JS packages
```

### 2. Verify everything locally (no funds, no network account)

```bash
make check            # build + Shanghai opcode check + unit tests + fork tests + typecheck
```

Expected result (exit 0):

- `✓ 10 bytecode blobs checked: Shanghai-safe.`
- Unit tests: **67/67 passed** (Checkout kit 11 · InvoiceCheckout 24 · PayeeRegistry 12 · AgentWallet 20)
- Fork tests against the real tUSD8: **7/7 passed** (kit 3 · AgentPay 4, including the over-budget revert)
- `pnpm -r typecheck` passes (examples + web)

Individual steps, if you want them separately: `make build`, `make test`,
`make test-fork`.

### 3. Run the app against a local copy of Aevum

```bash
# terminal 1: local copy of Aevum testnet on 127.0.0.1:8555 (chain 440050)
make fork

# terminal 2: deploy all contracts (Checkout + InvoiceCheckout + PayeeRegistry + AgentWallet)
make deploy-fork                      # prints all four addresses
make deal TO=<your wallet address>    # 100 tUSD8 + 10 tQDAY, on the fork only

# smoke test: create an invoice, pay the exact amount, require status Paid
make smoke-fork INVOICE_CHECKOUT=<address from deploy-fork>

cp web/.env.example web/.env.local
#   NEXT_PUBLIC_NETWORKS=fork,aevum
#   NEXT_PUBLIC_CHECKOUT_FORK=<address from deploy-fork>
make dev                              # http://localhost:3000
```

Want an empty chain instead of a fork? `make anvil` + `make deploy-local` deploys a
`MockUSD8` (same decimals, EIP-712 domain and EIP-3009 functions as tUSD8) that
anyone can mint with `make mint`.

### 4. Deploy to Aevum testnet (chain 44005)

You need test funds first: join the [QDay Discord](https://discord.gg/bYPhjmrSfK),
react ✅ in `#verify`, then run `/faucet <your address>` — you get **1 tQDAY + 5 tUSD8**,
once per Discord account and once per address. (The web faucet requires a small
Ethereum mainnet balance, so it is not usable for a fresh test-only wallet.)

```bash
cast wallet import aevum-deployer --interactive   # paste the key of a TEST wallet
cast wallet address --account aevum-deployer      # fund this address from the faucet

make deploy-aevum ACCOUNT=aevum-deployer          # uses real tUSD8; MERCHANT/OWNER default to the deployer
# MERCHANT=0x... OWNER=0x... make deploy-aevum ACCOUNT=aevum-deployer
```

The script prints all four deployed addresses. Record them with the exact commit
SHA in this README's [live deployment](#agentpay-invoice--live-deployment-aevum-builder-challenge-1)
section — **contract verification on the explorer does not work yet**, so the
addresses + the exact commit are the official reference (see also
[Deploy to Aevum testnet](#deploy-to-aevum-testnet)).

### 5. Run the proof scenarios

With the deployed addresses in `examples/.env` (copy `examples/.env.example` first):

```bash
# Scenario: agent pays one invoice gaslessly, after a Confirmation-of-Payee
# check and the AgentWallet guard rails
INVOICE_CHECKOUT_ADDRESS=0x... PAYEE_REGISTRY_ADDRESS=0x... \
  AGENT_WALLET_ADDRESS=0x... INVOICE_ID=0x... PAYEE_NAME=<name> \
  pnpm example pay-invoice-agent
```

Or run the kit's gasless flow against the kit `Checkout`:

```bash
pnpm example check-setup      # chain, block, gas price and balances of ADDRESS
pnpm example pay-gasless      # BUYER_KEY signs, RELAYER_KEY submits
pnpm example read-payments    # every Paid event, 1,000 blocks at a time
```

Verify each result on chain: `statusOf(invoiceId)` must read `2` (`Paid`), and the
payee's tUSD8 balance must have grown by exactly the invoice amount. The live
proof transactions for scenarios #1–#5 are linked in the
[live deployment](#agentpay-invoice--live-deployment-aevum-builder-challenge-1) section.

---

## Contents

- [AgentPay Invoice — live deployment](#agentpay-invoice--live-deployment-aevum-builder-challenge-1)
- [AgentPay Invoice — problem, architecture, workflow](#agentpay-invoice--problem-architecture-workflow)
- [Environment variables](#environment-variables)
- [Reproduce from scratch (turnkey)](#reproduce-from-scratch-turnkey)
- [Quickstart (5 minutes, no funds needed)](#quickstart-5-minutes-no-funds-needed)
- [Network details](#network-details)
- [Get test tokens](#get-test-tokens)
- [Deploy to Aevum testnet](#deploy-to-aevum-testnet)
- [Deploy the web app to Vercel](#deploy-the-web-app-to-vercel)
- [How the checkout works](#how-the-checkout-works)
- [Things that differ from Ethereum](#things-that-differ-from-ethereum)
- [Project layout](#project-layout)
- [Commands](#commands)
- [Submitting your project](#submitting-your-project)
- [FAQ](#faq)

---

## Quickstart (5 minutes, no funds needed)

You need [Node 22+](https://nodejs.org), [pnpm](https://pnpm.io/installation) and [Foundry](https://book.getfoundry.sh/getting-started/installation) (`foundryup`).

```bash
git clone --recursive https://github.com/qday-io/aevum-starter-kit.git
cd aevum-starter-kit
make install          # Solidity libs + JS packages
make check            # build, Shanghai opcode check, unit tests, fork tests
```

Run the whole app against a **local copy of Aevum**, with the real tUSD8 and free test balances:

```bash
# terminal 1: local copy of Aevum testnet on 127.0.0.1:8555 (chain 440050)
make fork

# terminal 2: deploy Checkout and give yourself test money
make deploy-fork                      # prints the Checkout address
make deal TO=<your wallet address>    # 100 tUSD8 + 10 tQDAY, on the fork only

cp web/.env.example web/.env.local
#   NEXT_PUBLIC_NETWORKS=fork,aevum
#   NEXT_PUBLIC_CHECKOUT_FORK=<address from deploy-fork>
#   RELAYER_PRIVATE_KEY=<a test key, see below>   (optional: enables gasless mode)
make dev                              # http://localhost:3000
```

Use the **Local fork / Aevum testnet** switcher in the app's header. The first time you pick the fork, your wallet offers to add "Aevum fork (local)" as a new network; after that, switching is one click and your real testnet network stays untouched.

**Why the fork has its own chain ID (440050):** it copies Aevum's state (accounts, balances, tUSD8) but anything you sign there, such as an EIP-3009 authorization or a permit, can't be replayed on the real testnet, and wallets never mix the two up. `make deploy-fork` also deploys from a random address nobody has the key to, so its contract addresses can't be claimed on the real testnet.

For a local relayer, any of anvil's [default test accounts](https://book.getfoundry.sh/anvil/#getting-started) works. Those keys are public, so the relayer refuses them on any chain but `make fork` and `make anvil`. When you add `aevum`, put a fresh test wallet's key in `RELAYER_PRIVATE_KEY` instead.

Want an empty chain instead of a fork? `make anvil` + `make deploy-local` deploys a `MockUSD8` (same decimals, EIP-712 domain and EIP-3009 functions as tUSD8) that anyone can mint with `make mint`.

---

## Network details

| | |
|---|---|
| Network | QDay Aevum Testnet |
| Chain ID | `44005` |
| RPC | `https://rpc-test.qday.info` (HTTPS only, no WebSocket) |
| Explorer | https://explorer-test.qday.info |
| Gas token | tQDAY (18 decimals) |
| Gas price | about 1 gwei. 1 tQDAY covers hundreds of contract calls. |
| EVM version | **Shanghai** |
| tUSD8 | [`0x456569838f1d43009A91ebA4263147Afd7233483`](https://explorer-test.qday.info/address/0x456569838f1d43009A91ebA4263147Afd7233483), 6 decimals, USDC-style (EIP-2612 `permit`, EIP-3009 signed transfers), EIP-712 domain `name: "tUSD8"`, `version: "2"` |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` |

All of this is in [`packages/aevum/src/chain.ts`](packages/aevum/src/chain.ts) and [`contracts.ts`](packages/aevum/src/contracts.ts).

---

## Get test tokens

- **Discord faucet (for Builder Challenge participants):** join the [QDay Discord](https://discord.gg/bYPhjmrSfK), react ✅ in `#verify`, then run `/faucet <your address>`. You get **1 tQDAY + 5 tUSD8**, once per Discord account and once per address. No Ethereum mainnet balance needed.
- **Web faucet:** https://faucet.qday.info. Check the page for its rules.
- **Local fork:** `make deal TO=<address>` for unlimited test balances. Nothing leaves your machine.

1 tQDAY is plenty for development: deploying `Checkout` costs well under 0.01 tQDAY.

---

## Deploy to Aevum testnet

Keep your deployer key out of files and shell history. Foundry's encrypted keystore asks for the key once and a password each time:

```bash
cast wallet import aevum-deployer --interactive   # paste the key of a TEST wallet
cast wallet address --account aevum-deployer      # fund this address from the faucet

make deploy-aevum ACCOUNT=aevum-deployer          # uses real tUSD8; MERCHANT defaults to the deployer
# MERCHANT=0x... make deploy-aevum ACCOUNT=aevum-deployer   to send payments elsewhere
```

Then set `NEXT_PUBLIC_CHECKOUT_AEVUM` in `web/.env.local` and add `aevum` to `NEXT_PUBLIC_NETWORKS`.

**Putting the web app online:** see [Deploy the web app to Vercel](#deploy-the-web-app-to-vercel). The same settings apply to any other host.

> Use a wallet made only for testing. Never paste a private key into chat, an issue, or a committed file.

**Contract verification:** the explorer's verifier isn't working yet, so `forge verify-contract` will fail for now. Put your contract addresses and a link to the source (the exact commit) in your README and submission instead. The command, for when it's back:

```bash
forge verify-contract <address> src/Checkout.sol:Checkout --chain-id 44005 \
  --verifier blockscout --verifier-url https://explorer-test.qday.info/api/
```

---

## Deploy the web app to Vercel

Deploy your contract first ([above](#deploy-to-aevum-testnet)), then:

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fqday-io%2Faevum-starter-kit&root-directory=web&project-name=aevum-starter-kit&repository-name=aevum-starter-kit&env=NEXT_PUBLIC_NETWORKS%2CNEXT_PUBLIC_CHECKOUT_AEVUM%2CTRUSTED_IP_HEADER&envDefaults=%7B%22NEXT_PUBLIC_NETWORKS%22%3A%22aevum%22%2C%22TRUSTED_IP_HEADER%22%3A%22x-vercel-forwarded-for%22%7D&envDescription=Your%20Checkout%20address%20from%20%60make%20deploy-aevum%60.%20Add%20RELAYER_PRIVATE_KEY%20later%20in%20Project%20Settings%20to%20turn%20on%20gasless%20checkout.&envLink=https%3A%2F%2Fgithub.com%2Fqday-io%2Faevum-starter-kit%23deploy-the-web-app-to-vercel)

The button copies this repo into your GitHub account and creates a Vercel project with **Root Directory** `web`. It asks for:

| Variable | Value |
|---|---|
| `NEXT_PUBLIC_NETWORKS` | `aevum` (prefilled). Keep it to `aevum` online: with `fork` or `local`, visitors get a "Local fork" option that points at *their own* 127.0.0.1. |
| `NEXT_PUBLIC_CHECKOUT_AEVUM` | Your Checkout address from `make deploy-aevum`. |
| `TRUSTED_IP_HEADER` | `x-vercel-forwarded-for` (prefilled). The relayer rate-limits on this header, which Vercel sets and visitors can't fake. |

Optional, in **Project Settings → Environment Variables** (then redeploy):

| Variable | Value |
|---|---|
| `RELAYER_PRIVATE_KEY` | Turns on gasless checkout. A **fresh** wallet with a little tQDAY, never one that holds anything else, and never an anvil key (the relayer refuses those on Aevum). Mark it Sensitive. |
| `NEXT_PUBLIC_DEPLOY_BLOCK_AEVUM` | Your deploy block. The Activity page starts scanning there. |
| `NEXT_PUBLIC_WC_PROJECT_ID` | Enables WalletConnect (mobile wallets). Free at [cloud.reown.com](https://cloud.reown.com). |
| `NEXT_PUBLIC_REPO_URL` | Your repo, for the Docs page's Source link. |

Doing it by hand instead: **Add New → Project**, import your repo, set **Root Directory** to `web`, add the variables above, and deploy. Keep the whole repo connected (not just `web/`): the app imports `packages/aevum` through the pnpm workspace, and Vercel reads `pnpm-lock.yaml` at the repo root.

> **The relayer's limits live in memory.** On Vercel each function instance has its own copy, so they slow down an attacker but don't stop one. Keep only a little tQDAY in the relayer, and move the limits to a shared store (for example Upstash Redis) if your app gets real traffic.

---

## How the checkout works

`Checkout` takes one token and one merchant address. Each `orderId` (any `bytes32`) can be paid once; the money goes straight to the merchant and the `Paid(orderId, payer, amount)` event is the receipt.

**Standard** (two transactions, buyer pays gas):

```
buyer ── approve(Checkout, amount) ──▶ tUSD8
buyer ── pay(orderId, amount) ───────▶ Checkout ── transferFrom ──▶ merchant
```

**Gasless** (one signature, the buyer needs no tQDAY):

```
buyer  ── signs ReceiveWithAuthorization(from, to=Checkout, value, validAfter, validBefore, nonce) ── off-chain
relayer ── payWithAuthorization(orderId, from, amount, …, v, r, s) ──▶ Checkout
           Checkout ── receiveWithAuthorization ──▶ tUSD8 ──▶ Checkout ──▶ merchant
```

Design choices you can reuse:

- The signed `nonce` must equal `Checkout.authorizationNonce(orderId)`. That binds the signature to one order, so a relayer can't reuse it to mark a different order as paid.
- `receiveWithAuthorization` (not `transferWithAuthorization`) means only the Checkout can pull the funds, so nobody can front-run the signature into a plain transfer.
- The contract doesn't know prices. Your app decides what an order costs (`priceOf` in [`web/src/lib/order.ts`](web/src/lib/order.ts)) and checks `paymentOf(orderId)` **and its amount** before delivering.

The web relayer ([`web/src/app/api/relay/route.ts`](web/src/app/api/relay/route.ts)) pays gas for anyone who calls it, so it has rails. Keep them if you build on it:

- It only calls `payWithAuthorization` on your Checkout, never anything else.
- It only relays the price your app set for that order. Otherwise anyone could burn your gas with 0.000001 tUSD8 payments.
- It skips orders that are already paid or already being submitted, and simulates before sending.
- It refuses anvil's public keys on a real network, caps the signature window at 1 hour, and rate-limits per IP and per payer with a daily cap.
- **The limits live in memory.** That works for `next start` on one server. On serverless hosts each instance has its own copy, so move them to a shared store (Redis, your database) before going live. Set `TRUSTED_IP_HEADER` to your host's client-IP header (`x-vercel-forwarded-for` on Vercel, `cf-connecting-ip` behind Cloudflare).

Known limits of this example contract, worth fixing in yours:

- **Anyone can pay any order, with any amount.** `pay(orderId, 1)` marks an order as paid for 0.000001 tUSD8, and can front-run the real buyer (whose transaction then reverts with `AlreadyPaid`). Never ship on `isPaid` alone: compare the amount (and the payer, if it matters). For production, key payments by `keccak256(payer, orderId)` or have the merchant sign each quote.
- Use unguessable order ids (the app uses random 32 bytes). Sequential invoice numbers can be claimed in advance.
- The merchant is fixed at deploy time, and tokens sent straight to the contract are stuck.

Code to read, in order:

1. [`contracts/src/Checkout.sol`](contracts/src/Checkout.sol)
2. [`contracts/test/Checkout.t.sol`](contracts/test/Checkout.t.sol): every rule above as a test
3. [`contracts/test/fork/AevumFork.t.sol`](contracts/test/fork/AevumFork.t.sol): the same flows against the real tUSD8
4. [`examples/src/pay-gasless.ts`](examples/src/pay-gasless.ts): sign + relay in about 40 lines
5. [`web/src/app/checkout/page.tsx`](web/src/app/checkout/page.tsx): both modes in the UI

---

## Things that differ from Ethereum

| | What happens | What to do |
|---|---|---|
| **Shanghai EVM** | Cancun opcodes (`MCOPY`, `TSTORE`/`TLOAD`, blob ops) don't exist. Code compiled for Cancun deploys fine, then reverts with `invalid opcode`. | Keep `evm_version = "shanghai"` in `foundry.toml` (already set). `make build` runs [`tools/check-shanghai.mjs`](tools/check-shanghai.mjs) to catch it. Don't use OpenZeppelin's `*Transient` contracts. |
| **anvil hides it** | A plain `anvil --fork-url` runs Cancun, so bad bytecode passes local tests. | Always add `--hardfork shanghai` (the Makefile does). |
| **1,000-block log limit** | `eth_getLogs` over more than 1,000 blocks fails. | Use `getLogsChunked` from `@aevum-kit/aevum`. Store your deploy block and start from there. |
| **No WebSocket RPC** | `watchContractEvent` over WS won't connect. | Poll over HTTPS (viem's default for `http()` transports). |
| **Explorer verification** | Not working yet. | See [Deploy](#deploy-to-aevum-testnet). |
| **Legacy transactions** | The kit's scripts and relayer send legacy (type 0) transactions, the same as QDay's own faucet. | `--legacy` in `forge script`, `type: "legacy"` in viem. |

---

## Project layout

```
contracts/            Foundry project
  src/Checkout.sol      the example contract
  src/mocks/MockUSD8.sol  local tUSD8 stand-in (anyone can mint)
  test/                 unit tests + test/fork (real tUSD8 on a fork)
  script/Deploy.s.sol   deploys to anvil, a fork or Aevum
packages/aevum/       chain config, ABIs, EIP-3009 typed data, getLogsChunked
web/                  Next.js app (wagmi + RainbowKit)
  src/app/page.tsx        Setup check
  src/app/checkout/       standard + gasless checkout
  src/app/receipts/       receipt read from the chain
  src/app/activity/       Paid events, read in 1,000-block chunks
  src/app/api/relay/      gasless relayer (server-side)
  src/app/globals.css     every color and font; edit to rebrand
examples/             runnable TypeScript scripts
tools/check-shanghai.mjs  fails the build on Cancun-only opcodes
LICENSE, NOTICE.md     MIT license and third-party licenses
```

---

## Commands

```
make install        Fetch Solidity libs and JS packages
make build          Compile contracts and check they are Shanghai-safe
make test           Unit tests (local, no network)
make test-fork      Tests against the real tUSD8 on a local fork of Aevum
make check          Build, tests and typecheck (CI also runs pnpm build)
make anvil          Empty local chain (31337) with Aevum's EVM rules
make fork           Local copy of Aevum testnet on 127.0.0.1:8555 (chain 440050)
make deploy-local   Deploy MockUSD8 + Checkout to `make anvil`
make deploy-fork    Deploy Checkout (real tUSD8) to `make fork`
make deploy-aevum   Deploy Checkout to Aevum testnet (ACCOUNT=<keystore>)
make mint           `make anvil` only: mint MockUSD8 (TO=, CHECKOUT=, AMOUNT=)
make deal           `make fork` only: give TO tUSD8 and tQDAY
make dev            Start the web app on http://localhost:3000
```

Examples (copy `examples/.env.example` to `examples/.env` first):

```bash
pnpm example check-setup      # chain, block, gas price and balances of ADDRESS
pnpm example pay-gasless      # BUYER_KEY signs, RELAYER_KEY submits
pnpm example read-payments    # every Paid event, 1,000 blocks at a time
```

---

## Submitting your project

Make it easy for judges to check your on-chain activity:

- Contract addresses on Aevum testnet (`44005`), with explorer links.
- A link to the exact commit you deployed.
- A few transaction hashes that show your app working (the receipt page and the activity page show them).
- A short demo video or a live URL.

Read the official rules on the DoraHacks challenge page. They win over anything here.

### Licenses and credit

The organizers confirmed that boilerplate, scaffolding and templates are allowed, as long as their license permits the use. This kit is MIT licensed, so you can build on it.

- Put a permissive open-source license on your repo, usually MIT or Apache 2.0.
- If you start from this kit, keep its `LICENSE` file (or its copyright notice) and say so in your README, for example: "Based on Aevum Starter Kit (MIT, PQA Labs)".
- Keep the original copyright and license headers in any file you copy from another project.
- Put a short comment above any code snippet you borrow, naming the source repo, author and license.
- List your third-party dependencies and their licenses in your README or a `NOTICE` file. [NOTICE.md](NOTICE.md) shows one way to do it.
- If you copy a whole directory or library, keep its original `LICENSE` file in that folder.

---

## FAQ

**Do I have to use `Checkout`?** No. It's an example. Keep the parts you need (`packages/aevum`, the chunked log reader, the setup checker) and replace the rest.

**Can I use account abstraction?** It isn't required for this challenge, and there's no officially supported bundler or paymaster. A normal wallet plus tUSD8 payments is enough. To spare users gas, use the gasless checkout in this kit (EIP-3009 with a relayer). For budgets, limits, expiry and revoke, write them into your own contract. You can deploy your own ERC-4337 setup if you want to, but the team won't support or debug it.

**Can I use Hardhat?** Yes. Set `evmVersion: "shanghai"` in the Solidity settings, and `hardfork: "shanghai"` for the Hardhat network.

**My transaction fails with `invalid opcode`.** You compiled for Cancun. See [Things that differ from Ethereum](#things-that-differ-from-ethereum).

**`eth_getLogs` errors on a big range.** Split it into 1,000-block chunks with `getLogsChunked`.

**Where do I ask for help?** In the [QDay Discord](https://discord.gg/bYPhjmrSfK)'s Builder Challenge channels (verify first to see them), Monday to Friday, 10:00 to 18:00 HKT.

**`pnpm audit` reports high advisories in `zod` and `decode-uri-component`.** Both come in through WalletConnect (`@reown/appkit-wallet` pins `zod` 3.22.4; `@walletconnect/utils` 2.21 uses `query-string`). They run only in the browser, are only reached when you set `NEXT_PUBLIC_WC_PROJECT_ID`, and at worst slow down the user's own tab. The relay route doesn't load them. The fix is upstream: RainbowKit moving to wagmi 3 brings WalletConnect 2.26, which drops `query-string`. Forcing newer versions with `pnpm.overrides` swaps in major versions WalletConnect wasn't tested with, so the kit doesn't.

---

MIT licensed, © 2026 PQA Labs. See [LICENSE](LICENSE). Third-party licenses are listed in [NOTICE.md](NOTICE.md).
