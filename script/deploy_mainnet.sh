#!/usr/bin/env bash
set -euo pipefail

RPC="${POLYGON_RPC_URL:-https://polygon-bor-rpc.publicnode.com}"
PK="${PRIVATE_KEY:?PRIVATE_KEY required}"
OWNER="${OWNER:?OWNER required}"

cd "$(dirname "$0")/.."

echo "Compiling ArbExecutor MAIN (-f)..."
INIT=$(huffc src/ArbExecutor.huff MAIN -f --evm-version shanghai)

echo "Deploying runtime..."
DEPLOY_OUT=$(cast send --rpc-url "$RPC" --private-key "$PK" --gas-limit 5000000 --create "$INIT")
ADDR=$(echo "$DEPLOY_OUT" | awk '/contractAddress/ {print $2}')
STATUS=$(echo "$DEPLOY_OUT" | awk '/status/ {print $2}')
echo "Deployed: $ADDR (status=$STATUS)"

INIT_ARGS=$(cast calldata "initialize(address,address,address,address,address,address,address,address,address,address,address,address,address,address,address,address,address)" \
  "$OWNER" \
  0xBA12222222228d8Ba445958a75a0704d566BF2C8 \
  0x1F98431c8aD98523631AE4a59f267346ea31F984 \
  0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2 \
  0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28 \
  0x2Bef16A0081565E72100D73CBe19B1Bd2d802380 \
  0x794a61358D6845594F94dc1DB02A252b5b4814aD \
  0x67366782805870060151383F4BbFF9daB53e5cD6 \
  0x9e5a52f57b3038F1b8EEE45f28b3c196dE8ce761 \
  0xc35DADB65012eC5796536bD9864eD8773aBc74C4 \
  0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32 \
  0xE7Fb3e833eFE5F9c441105EB65Ef8b261266423B \
  0xCf083Be4164828f00cAE704EC15a36D711491284 \
  0x9F3044B7945fe442E9A4d76A047783e1d70DCF80 \
  0x668ad0Ed2622C62e24F0D5ab6B31E99125Ce0F46 \
  0x93bc755FC5d27fa1Fa7c146C0625D1Cd18914d54 \
  0x0000000000000000000000000000000000000001)

echo "Initializing storage..."
cast send "$ADDR" "$INIT_ARGS" --rpc-url "$RPC" --private-key "$PK" --gas-limit 500000

OWNER_ONCHAIN=$(cast call "$ADDR" "owner()(address)" --rpc-url "$RPC")
echo "owner() = $OWNER_ONCHAIN"
echo "EXECUTOR_ADDRESS=$ADDR"