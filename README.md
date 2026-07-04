# ArbExecutor

Flash-loan-powered arbitrage executor for Polygon. Written in Huff (hand-optimized assembly), deployed as deterministic bytecode. Zero upfront capital — swap principal comes from flash loans.

## Execution Modes

The contract exposes three owner-only entry points. All take the same `packedRoute` blob and return realized profit in the profit token.

| Function | Flash loan | Use when |
|----------|------------|----------|
| `executeArb` | Balancer V2 Vault | Default path; borrows via `flashLoan` → `receiveFlashLoan` |
| `executeArbWithAave` | Aave V3 Pool | When Balancer liquidity or fees are unfavorable |
| `executeArbDirect` | None | Balancer `batchSwap` / Vault flash-swap routes — the Vault is non-reentrant and cannot be called from inside `receiveFlashLoan` |

```
executeArb:          owner → flashLoan → receiveFlashLoan → [calls] → repay → profit check
executeArbWithAave:  owner → flashLoanSimple → executeOperation → [calls] → approve+repay → profit check
executeArbDirect:    owner → [calls] → profit check
```

The contract holds no working capital. Failed executions revert atomically (`InsufficientProfit`, `ExternalCallFailed`, etc.) — the owner only pays gas.

### State machine

`IDLE (0) → FLASHLOAN (1) → CALLBACK (2) → IDLE (0)`

Reentrancy is blocked outside callback phases. Balancer Vault calls inside a Vault flash-loan callback are rejected (`BalancerVaultReentrancy`).

## Route Format

Routes are ABI-packed by `ArbExecutorCodec` in `src/ArbExecutor.sol` (usable from off-chain code or tests):

```
flashToken | flashAmount | profitToken | minProfit | deadline | routeHash | calls[]
```

Each call in `calls[]` is `target | value | dataLen | data`. Up to 12 calls per route. `routeHash` must equal `keccak256(packedCalls)`; mismatch reverts with `InvalidRouteHash`.

`minProfit` is checked against the profit-token balance delta (final − starting). Unprofitable routes revert with `InsufficientProfit`.

Helper functions on the Solidity interface: `buildPackedRoute`, `packExecutorCalls`, `computeRouteHash`.

## Protocols

Pool-based DEX callbacks verify the caller against an on-chain factory lookup before paying tokens. Protocol IDs are embedded in swap calldata by the bot.

| ID | Category | Protocol | Callback |
|----|----------|----------|----------|
| 1 | V3 | Uniswap V3 | `uniswapV3SwapCallback` |
| 2 | V3 | SushiSwap V3 | `uniswapV3SwapCallback` |
| 6 | V3 | Ramses V3 | `uniswapV3SwapCallback` |
| 3 | Algebra | QuickSwap V3 | `algebraSwapCallback` |
| 4 | Algebra | QuickSwap V4 | `algebraSwapCallback` |
| — | V4 | Uniswap V4 | `unlockCallback` (via PoolManager) |
| 7–14 | V2 | Uniswap V2, SushiSwap V2, QuickSwap V2, DFYN, ApeSwap, MeshSwap, JetSwap, ComethSwap | `uniswapV2Call` |

**Arbitrary calls** — Curve, DODO V2, WooFi, Balancer `batchSwap`, and any other protocol are encoded as plain `target/value/data` steps in the route. The bot supplies full calldata (typically `approve` + `swap`). These have no dedicated callback handler.

V2/V3/Algebra callbacks pay via `transfer` (no standing approvals). Aave repayment auto-approves the pool inside `executeOperation`.

## Access Control

- `executeArb`, `executeArbDirect`, `executeArbWithAave` — owner only
- `approveIfNeeded`, `transferAll` — owner or contract itself (for in-route approvals)
- `preApprove`, `approveAll`, `rescueToken`, `rescueNative`, `withdraw`, `transferOwnership` — owner only

Set `OWNER` to the bot wallet at deploy time.

## Contracts

| File | Description |
|------|-------------|
| `src/ArbExecutor.huff` | Canonical implementation — swap logic, callbacks, flash-loan handlers, auth |
| `src/ArbExecutor.sol` | Abstract interface, errors, and `ArbExecutorCodec` helpers for route packing |
| `test/HuffDeployer.sol` | Compiles Huff via `ffi` + `huffc`; deploys constructor bytecode and `vm.etch`es runtime |
| `script/Deploy.s.sol` | Foundry broadcast deploy (constructor args embedded at deploy) |
| `script/deploy_mainnet.sh` | Alternative mainnet deploy via `cast` (runtime bytecode + post-deploy `initialize`) |
| `deploy` | Shell wrapper around `forge script script/Deploy.s.sol --broadcast` |

Deploy-time storage (slots 0–22): owner, Balancer Vault, V3/V2 factory addresses, Aave Pool, Uniswap V4 PoolManager, QuickSwap V4 factory placeholder.

## Setup

Requires [Foundry](https://book.getfoundry.sh/), `huffc` (`cargo install huffc`), and `ffi` enabled (already set in `foundry.toml`).

```bash
git submodule update --init --recursive
```

## Commands

```bash
# Build
forge build

# Unit tests (mocks, no RPC)
forge test --match-contract "AuthTest|AtomicTest|PrintTest" -vvv

# Fork tests (Polygon RPC via POLYGON_RPC_URL or --rpc-url)
forge test --match-contract "AaveFork|Debug" -vvv

# Deploy (Foundry script — constructor initializes storage)
OWNER=<0x...> RPC_URL=<url> PRIVATE_KEY=<key> ./deploy

# Deploy (cast — runtime bytecode + separate initialize call)
OWNER=<0x...> PRIVATE_KEY=<key> ./script/deploy_mainnet.sh
```

Test suites: `ArbExecutorAuth`, `ArbExecutorAtomic`, `ArbExecutorPrint` (local); `ArbExecutorAaveFork`, `ArbExecutorDebug` (forked).