# ArbExecutor

Flash-loan-powered arbitrage executor for Polygon. Hand-optimized Huff assembly with a Solidity codec/interface layer. Zero working capital — swap principal is borrowed, swapped, and repaid in one atomic transaction.

## Architecture

| Layer | Role |
|-------|------|
| `src/ArbExecutor.huff` | Canonical runtime — dispatch, flash-loan handlers, pool callbacks, auth, profit checks |
| `src/ArbExecutor.sol` | Abstract interface, custom errors, `ArbExecutorCodec`, Balancer/Aave interface types |
| `abis/` | Upstream Balancer V2 + Aave V3 flash-loan surfaces (reference only) |
| `test/HuffDeployer.sol` | Compiles Huff via `ffi` + `huffc`; CREATE + `vm.etch` for tests/scripts |
| `script/` | Deploy paths (Foundry broadcast vs cast + `initialize`) |

Requires Cancun (`TLOAD`/`TSTORE`) for callback-phase and DODO context. Configured in `foundry.toml` (`evm_version = "cancun"`, `ffi = true`).

## Execution Modes

Four owner-only entry points. Each returns `uint256 realizedProfit` in the profit token.

| Function | Flash loan | Use when |
|----------|------------|----------|
| `executeArb` | Balancer V2 Vault `flashLoan` → `receiveFlashLoan` | Default path |
| `executeArbWithAave` | Aave V3 Pool `flashLoanSimple` → `executeOperation` | Single-asset loan; Pool pulls `amount + premium` after callback |
| `executeArbWithDodo` | DODO V2 pool `dvmFlashLoan` → `dvm`/`dpp`/`dsp` flash-loan callback | Alt lender; see field semantics below |
| `executeArbDirect` | None | Balancer `batchSwap` / Vault flash-swaps — Vault is non-reentrant, so it cannot be called from `receiveFlashLoan` |

```
executeArb:           owner → flashLoan → receiveFlashLoan → [calls] → repay(transfer) → profit check
executeArbWithAave:   owner → flashLoanSimple → executeOperation → [calls] → approve → (Pool pulls amount+premium) → profit check
executeArbWithDodo:   owner → dvmFlashLoan → DODO callback → [calls] → repay(transfer) → profit check
executeArbDirect:     owner → [calls] → profit check
```

Failed routes revert atomically (`InsufficientProfit`, `ExternalCallFailed`, …). The owner pays gas only.

**DODO field semantics** (`executeArbWithDodo`): `flashToken` is the DODO pool address; the borrowed asset is `profitToken`; `flashAmount` is the base amount passed to `dvmFlashLoan` (quote amount is always `0`). Entry always uses the `dvmFlashLoan` selector; DVM/DPP/DSP pools may call back via different callback selectors, all handled by the same repay path.

**Bot integration:** sibling `rpbot` (`../c`) disables DODO flash dispatch until external (non-route) DODO lenders exist. Prefer `executeArb` / `executeArbWithAave` / `executeArbDirect` from off-chain routing.

### Phase machine (transient storage)

`IDLE (0) → FLASHLOAN (1) → CALLBACK (2) → IDLE (0)`

Phase lives in transient slot `0`. Callbacks outside the flash-loan window revert (`FlashLoanOnly` / `CallbackOnly` / related). Balancer Vault targets inside a Vault flash-loan callback are rejected (`BalancerVaultReentrancy`) via `VALIDATE_NO_VAULT_CALLS`.

A separate permanent reentrancy guard on storage slot `6` (`1` unlocked / `2` locked) protects `rescueToken` / `rescueNative` only.

## Route Format

Packed by `ArbExecutorCodec` (`src/ArbExecutor.sol`) — usable from bots and tests:

```
flashToken | flashAmount | profitToken | minProfit | deadline | routeHash | packedCalls
```

Each word above is 32 bytes. `packedCalls` is:

```
numCalls | (target | value | dataLen | data)×N
```

Constraints:

- **1–12 calls** (`EmptyRoute` / `TooManyCalls`)
- `routeHash` must equal `keccak256(packedCalls)` (`InvalidRouteHash`)
- `deadline` is compared to `block.timestamp` (`DeadlineExpired`)
- Flash modes require non-zero `flashAmount` (`FlashLoanRequired`) and non-zero token addresses (`ZeroAddress`)

Helpers: `buildPackedRoute`, `packExecutorCalls`, `computeRouteHash`.

### Profit check

`minProfit` is enforced against the profit-token balance delta:

| Mode | When checked | Effective balance |
|------|--------------|-------------------|
| Balancer / Direct / DODO | After push-repay | Final balance already excludes the loan |
| Aave V3 | Inside `executeOperation`, before approve | When `asset == profitToken`, `ASSERT_PROFIT_AAVE` subtracts `amount + premium` (Pool pulls after return). That post-pull effective balance is also used for the ABI `realizedProfit` return |

Unprofitable routes revert with `InsufficientProfit(finalBalance, requiredBalance)`.

## Protocols

Pool swap callbacks verify `msg.sender` against an on-chain factory lookup. Protocol IDs are embedded in swap calldata by the bot.

| ID | Category | Protocol | Callback |
|----|----------|----------|----------|
| 1 | V3 | Uniswap V3 | `uniswapV3SwapCallback` |
| 2 | V3 | SushiSwap V3 | `uniswapV3SwapCallback` |
| 3 | Algebra | QuickSwap V3 | `algebraSwapCallback` |
| 4 | Algebra | QuickSwap V4 | `algebraSwapCallback` |
| — | V4 | Uniswap V4 | `unlockCallback` (via PoolManager) |
| 7 | V2 | Uniswap V2 | `uniswapV2Call` |
| 8 | V2 | SushiSwap V2 | `uniswapV2Call` |
| 9 | V2 | QuickSwap V2 | `uniswapV2Call` |
| — | DODO | DODO V2 DVM/DPP/DSP | `dvmFlashLoanCall` / `dppFlashLoanCall` / `dspFlashLoanCall` |

**Arbitrary calls** — Curve, WooFi, Balancer `batchSwap`, DODO swaps (as route steps), and anything else are plain `target/value/data` steps. No dedicated callback; the bot supplies full calldata (typically `approve` + `swap`).

**Uniswap V4** — route step calls `PoolManager.unlock` with `abi.encode(PoolKey, SwapParams)` (8 words: `currency0, currency1, fee, tickSpacing, hooks, zeroForOne, amountSpecified, sqrtPriceLimitX96`). `unlockCallback` runs `swap` and settles both deltas (`sync → transfer → settle` for debt, `take` for credit). ERC20 only — native (`address(0)`) debt fails closed via PoolManager `CurrencyNotSettled`. Multi-hop V4 = multiple `unlock` steps.

V2/V3/Algebra callbacks pay via `transfer` (no standing approvals). Aave repayment auto-approves the Pool inside `executeOperation`. DODO repayment transfers the flash amount back to the pool inside the callback.

## Access Control

| Surface | Who |
|---------|-----|
| `executeArb`, `executeArbDirect`, `executeArbWithAave`, `executeArbWithDodo` | Owner |
| `approveIfNeeded`, `transferAll` | Owner **or** the contract itself (in-route) |
| `preApprove`, `approveAll`, `rescueToken`, `rescueNative`, `withdraw`, `withdrawToken`, `transferOwnership` | Owner |
| `initialize` | Once only (storage slot `0` must be zero); sets config slots |

Views (no auth): `owner`, `balancerVault`, V3/V2/Algebra factories, `aavePool`, `poolManager`, etc.

Set `OWNER` to the bot wallet at deploy. Cast-based mainnet deploy creates bare runtime then calls `initialize`; the Foundry script embeds the 11 constructor args at CREATE time.

## Storage Layout

| Slot | Contents |
|------|----------|
| `0x00` | Owner |
| `0x06` | Permanent reentrancy guard (`1` unlocked, `2` locked) — rescue paths |
| `0x07` | Balancer Vault |
| `0x08`–`0x0a` | Uni V3, Sushi V3, Quick V3 (Algebra) factories |
| `0x0b` | Aave V3 Pool |
| `0x0c` | Uniswap V4 PoolManager |
| `0x0d`–`0x0f` | Uni V2, Sushi V2, Quick V2 factories |
| `0x10` | QuickSwap V4 factory (may be a non-zero sentinel) |

Constructor / `initialize` take the same **11** addresses (owner + 10 protocol addresses), all non-zero. DODO pool/token context uses **transient** slots during execution only (not persistent storage).

## Layout

| Path | Description |
|------|-------------|
| `src/ArbExecutor.huff` | Implementation |
| `src/ArbExecutor.sol` | Interface, errors, codec |
| `test/HuffDeployer.sol` | Huff compile + deploy helpers |
| `test/ArbExecutorAtomic.t.sol` | Local mocks: routes, Aave premium profit, Vault reentrancy |
| `test/ArbExecutorAuth.t.sol` | Owner / non-owner auth |
| `test/ArbExecutorPrint.t.sol` | Deploy + `initialize` smoke |
| `test/ArbExecutorV4.t.sol` | Uniswap V4 unlock/settle (mocked PoolManager) |
| `test/ArbExecutorAaveFork.t.sol` | Forked Polygon Aave V3 surface checks |
| `test/ArbExecutorDebug.t.sol` | Forked debug harness |
| `test/HashDebug.t.sol` | Route-hash utility (dev) |
| `script/Deploy.s.sol` | Foundry broadcast deploy (constructor args) |
| `script/deploy_mainnet.sh` | Cast deploy: runtime CREATE + `initialize` |

## Setup

Requires [Foundry](https://book.getfoundry.sh/), `huffc` (`cargo install huffc`), and `ffi` (enabled in `foundry.toml`).

```bash
git submodule update --init --recursive
cp .env.example .env   # OWNER, PRIVATE_KEY, POLYGON_RPC_URL
```

## Commands

```bash
# Build (Solidity artifacts; Huff is compiled via huffc/ffi at deploy/test time)
forge build

# Unit tests (no RPC)
forge test --match-contract "AuthTest|AtomicTest|PrintTest|V4Test" -vvv

# Fork tests (POLYGON_RPC_URL; default https://polygon-bor-rpc.publicnode.com)
forge test --match-contract "AaveFork|Debug" -vvv

# Deploy — cast (runtime CREATE + initialize)
OWNER=0x... PRIVATE_KEY=0x... ./script/deploy_mainnet.sh

# Deploy — Foundry script (constructor-embedded config)
# Requires OWNER; uses PRIVATE_KEY / --private-key for broadcast
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url "${POLYGON_RPC_URL:-https://polygon-bor-rpc.publicnode.com}" \
  --broadcast --private-key "$PRIVATE_KEY"
```

Polygon protocol addresses used by both deploy paths are hardcoded in `script/Deploy.s.sol` and `script/deploy_mainnet.sh` (Balancer Vault, factories, Aave Pool, V4 PoolManager).
