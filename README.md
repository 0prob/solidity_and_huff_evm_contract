# ArbExecutor

Flash-loan-powered arbitrage executor for Polygon. Written in Huff (hand-optimized assembly), deployed as deterministic bytecode. Zero upfront capital — all swaps are funded by flash loans.

## 0-Capital Design

```
Bot → flashLoan(executeArb) → swap A→B → swap B→A → repay loan → profit to bot
```

The contract holds no funds. Every `executeArb` (Balancer V2) or `executeArbWithAave` (Aave V3) borrows the full swap principal. Callback handlers repay the loan before the flash loan provider can enforce a revert. Failed executions revert atomically — no stuck funds.

State machine: `IDLE → FLASHLOAN → CALLBACK → IDLE`

If the arbitrage is unprofitable, the transaction reverts (`InsufficientProfit`). The bot only pays gas for failed attempts.

## Protocols

| Category | Protocols | Callback |
|----------|-----------|----------|
| V3 | Uniswap V3, SushiSwap V3, Ramses V3 | `uniswapV3SwapCallback` |
| Algebra | QuickSwap V3, QuickSwap V4 | `algebraSwapCallback` |
| V4 | Uniswap V4 | `lockAcquired` |
| V2 | Uniswap V2, SushiSwap V2, QuickSwap V2, DFYN, ApeSwap, MeshSwap, JetSwap, ComethSwap | `uniswapV2Call` |
| Generic | Curve, DODO V2, WooFi | direct (bot-encoded) |
| Flash Loans | Balancer V2, Aave V3 | — |

Pool addresses verified via factory lookup before each swap. V2/V3/V4 protocols pay via transfer (no approvals). Generic protocols use approve+swap encoded in the route.

## Contracts

| File | Description |
|------|-------------|
| `src/ArbExecutor.huff` | Canonical contract — all swap logic, callbacks, auth, pool verification |
| `src/ArbExecutor.sol` | Solidity reference — matches Huff interface for tooling/audit |
| `test/HuffDeployer.sol` | Bundles compiled Huff bytecode; used by tests and deploy script |
| `script/Deploy.s.sol` | Foundry deploy script |

## Setup

Requires [Foundry](https://book.getfoundry.sh/) and `huffc` (`cargo install huffc`).

```bash
# Initialize and install needed libs
forge init
```

## Commands

```bash
# Build
forge build

# Unit tests (no fork needed)
forge test --match-contract "AuthTest|AtomicTest|PrintTest" -vvv

# Fork tests (needs Polygon RPC)
forge test --match-contract "AaveFork|Debug" -vvv

# Deploy
OWNER=<0x...> RPC_URL=<url> PRIVATE_KEY=<key> ./deploy
```

