# ArbExecutor

Flash-loan-powered arbitrage execution contract for EVM chains (Polygon mainnet default).

## Contracts

| Contract | Description |
|----------|-------------|
| `src/ArbExecutor.sol` | Core arbitrage executor using Balancer V2 and Aave V3 flash loans. Supports Uniswap V3/V4, SushiSwap V3, QuickSwap V3, Kyber Elastic, and Ramses V3. Owner-only access, non-reentrant, phase-machine state management. |

## Setup

```bash
forge install
```

Requires [Foundry](https://book.getfoundry.sh/).

## Usage

```bash
# Build
forge build

# Test
forge test

# Test with fork (Polygon mainnet)
forge test --fork-url $RPC_URL --match-path test/ArbExecutorAaveFork.t.sol -vvv

# Deploy
OWNER=<0x...> RPC_URL=<url> PRIVATE_KEY=<key> ./deploy

## Deployments

Deployment bytecode is compiled via Huff and inlined in `test/HuffDeployer.sol`. See `script/ArbExecutor.s.sol` for default addresses.

## Architecture

- Flash loan entrypoints: `executeArb` (Balancer), `executeArbWithAave` (Aave)
- State machine: `IDLE → FLASHLOAN → CALLBACK → IDLE`
- Callback source verification against known DEX factories
- Atomic execution — failed routes revert intermediate state