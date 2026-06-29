# ArbExecutor

Flash-loan-powered arbitrage execution contract for Polygon mainnet.
Written in Huff (hand-optimized assembly), deployed as deterministic bytecode.

## Supported Protocols

| Category | Protocol | Swap Interface | Callback |
|----------|----------|---------------|----------|
| V3 | Uniswap V3 | `pool.swap()` | `uniswapV3SwapCallback` |
| V3 | SushiSwap V3 | `pool.swap()` | `uniswapV3SwapCallback` |
| V3 | Ramses V3 | `pool.swap()` | `uniswapV3SwapCallback` |
| Algebra | QuickSwap V3 | `pool.swap()` | `algebraSwapCallback` |
| Algebra | QuickSwap V4 | `pool.swap()` | `algebraSwapCallback` |
| V4 | Uniswap V4 | `poolManager.swap()` | `lockAcquired` |
| V2 | Uniswap V2 | `pair.swap()` | `uniswapV2Call` |
| V2 | SushiSwap V2 | `pair.swap()` | `uniswapV2Call` |
| V2 | QuickSwap V2 | `pair.swap()` | `uniswapV2Call` |
| V2 | DFYN | `pair.swap()` | `uniswapV2Call` |
| V2 | ApeSwap | `pair.swap()` | `uniswapV2Call` |
| V2 | MeshSwap | `pair.swap()` | `uniswapV2Call` |
| V2 | JetSwap | `pair.swap()` | `uniswapV2Call` |
| V2 | ComethSwap | `pair.swap()` | `uniswapV2Call` |
| Generic | Curve, DODO V2, WooFi | direct call (bot-encoded) | none needed |
| Flash | Balancer V2, Aave V3 | flash loan providers | — |

All callback-based protocols verify pool addresses via factory lookup before paying. Generic protocols execute via the route Call array (token.approve + swap in sequence) — no contract changes needed.

## Contracts

| File | Description |
|------|-------------|
| `src/ArbExecutor.huff` | Huff source — the canonical contract (941→1150 lines). All swap logic, callbacks, auth, reentrancy, pool verification. |
| `src/ArbExecutor.sol` | Solidity reference — matches Huff interface for tooling/audit. Does NOT compile to deployed contract. |
| `test/HuffDeployer.sol` | Inlines compiled Huff bytecode + deployment helpers. Used by scripts and tests. |
| `script/ArbExecutor.s.sol` | Deploy script — reads env vars, deploys via HuffDeployer bytecode. |

## Protocol IDs

| ID | Protocol | Action |
|----|----------|--------|
| 1 | Uniswap V3 | `uniswapV3SwapCallback` |
| 2 | SushiSwap V3 | `uniswapV3SwapCallback` |
| 3 | QuickSwap V3 | `algebraSwapCallback` |
| 4 | QuickSwap V4 | `algebraSwapCallback` |
| 5 | Uniswap V4 | `lockAcquired` |
| 6 | Ramses V3 | `uniswapV3SwapCallback` |
| 7–14 | V2 forks | `uniswapV2Call` |

Bot encodes protocol ID in callback data. Pool resolution matches ID to factory address. Curve (15), DODO (16), WooFi (17) use generic encode — no IDs needed.

## Error Selectors

| Selector | Error |
|----------|-------|
| `0x82b42900` | Unauthorized |
| `0x1ab7da6b` | DeadlineExpired |
| `0xea60ab1d` | EmptyRoute |
| `0xf5dedbff` | TooManyCalls |
| `0x946302fe` | FlashLoanRequired |
| `0xc858adff` | InvalidRouteHash |
| `0xfc305329` | FlashLoanOnly |
| `0xadd4adc0` | InvalidFlashLoanContext |
| `0xc21d53e8` | CallbackOnly |
| `0xf850442b` | UnsupportedProtocol |
| `0xf2062559` | InvalidPoolCaller |
| `0x0f434573` | ExternalCallFailed |
| `0x4e88422a` | InsufficientProfit |
| `0xbf182be8` | TransferFailed |
| `0x1b6c83ab` | ApproveFailed |
| `0xd92e233d` | ZeroAddress |
| `0x936198e9` | InvalidCallbackSource |

## Setup

```bash
forge install
```
Requires [Foundry](https://book.getfoundry.sh/) and `huffc` (install via `cargo install huffc`).

## Usage

```bash
# Build tests/scripts
forge build

# Run tests (non-fork)
forge test --match-contract "AuthTest|AtomicTest|PrintTest" -vvv

# Run fork tests (needs Polygon RPC)
forge test --match-contract "AaveFork|Debug" -vvv

# Deploy
OWNER=<0x...> RPC_URL=<url> PRIVATE_KEY=<key> ./deploy
```

## Recompiling Huff

```bash
huffc src/ArbExecutor.huff --bytecode
# → paste hex output into test/HuffDeployer.sol BYTECODE constant
```

## Architecture

- Flash loan entrypoints: `executeArb` (Balancer V2), `executeArbWithAave` (Aave V3)
- State machine: `IDLE → FLASHLOAN → CALLBACK → IDLE`
- Pool verification: factory lookup → staticcall → assert caller matches
- Non-reentrant: `_locked` guard with pre/post checks
- Permissionless operation: `approveAll(token)` pre-approves all 16 protocol addresses at once. Callback-based protocols (V2/V3/V4) pay via transfer — no approvals needed. Generic protocols (Curve, DODO, WooFi) use approve+swap in route Call array.
- Atomic execution — failed calls revert all state