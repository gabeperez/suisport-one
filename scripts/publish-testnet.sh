#!/usr/bin/env bash
# SuiSport — testnet publish helper.
#
# Runs `sui move build` + `sui client publish` from move/suisport, then
# prints the wrangler commands you need to copy into the Worker's
# environment so the pipeline goes live.
#
# Pre-reqs:
#   - sui CLI installed and at v1.x
#   - `sui client` already configured (run `sui client new-env --alias testnet`
#     and `sui client switch --env testnet` once, then `sui client faucet` to
#     fund your default address)
#   - wrangler authenticated (perez-jg22 account by default)
#
# What this does NOT do:
#   - Initialize RewardsEngine (you need the AdminCap — run a second PTB
#     after publish to call `rewards_engine::initialize` with your
#     chosen epoch_cap + per_user_cap + initial Version object).
#   - Mint the OracleCap (call `admin::mint_oracle(admin, pubkey)` in a
#     PTB and share the resulting OracleCap or transfer to operator).

set -euo pipefail

cd "$(dirname "$0")/../move/suisport"

echo "▸ Building Move package…"
sui move build 2>&1 | tail -4

echo
echo "▸ Switching to testnet env…"
sui client switch --env testnet 2>/dev/null || {
    echo "  (no testnet env — creating…)"
    sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
    sui client switch --env testnet
}

ADDR=$(sui client active-address 2>/dev/null || echo "")
echo "▸ Active address: $ADDR"

BAL=$(sui client gas 2>&1 | head -20 || true)
if echo "$BAL" | grep -q "No gas"; then
    echo "▸ No gas — requesting from faucet…"
    sui client faucet || true
    sleep 2
fi

echo
echo "▸ Publishing package…"
OUT=$(sui client publish --gas-budget 500000000 --json 2>&1)
echo "$OUT" > /tmp/suisport-publish.json

PKG=$(echo "$OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('objectChanges', []):
    if c.get('type') == 'published':
        print(c['packageId']); break
")

if [[ -z "$PKG" ]]; then
    echo "✘ Failed to extract packageId. Full output at /tmp/suisport-publish.json"
    exit 1
fi

echo "✓ Package published: $PKG"
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Next: initialize RewardsEngine via the AdminCap transferred"
echo "  to your active address. Object ids to capture from the"
echo "  initialize / mint_oracle PTBs:"
echo
echo "    - RewardsEngine (shared)"
echo "    - OracleCap (owned by operator)"
echo "    - Version (shared)"
echo
echo "  Once you have them, paste into wrangler:"
echo
echo "    cd cloudflare"
echo "    wrangler secret put SUI_PACKAGE_ID          # $PKG"
echo "    wrangler secret put SUI_REWARDS_ENGINE_ID   # 0x..."
echo "    wrangler secret put SUI_ORACLE_CAP_ID       # 0x..."
echo "    wrangler secret put SUI_VERSION_OBJECT_ID   # 0x..."
echo "    wrangler secret put SUI_OPERATOR_KEY        # base64 of operator private key"
echo "    wrangler secret put ORACLE_PRIVATE_KEY      # base64 of oracle ed25519 private key"
echo "    wrangler deploy"
echo
echo "  Then curl /v1/sui/status to confirm \`configured: true\`."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
