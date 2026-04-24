# Testnet setup — end-to-end

This flips every stubbed component into the real thing on Sui testnet.
After you've run through it, a workout submission produces a real
$SWEAT mint, a soulbound on-chain Workout object, and a Walrus blob
containing the canonical payload — all verifiable on explorer.

**You need to do the ordered steps yourself** — I can't publish
contracts from a sandbox without your keys.

---

## 0. Prereqs

- macOS with Homebrew
- Node 20+
- Wrangler logged in as you (`wrangler whoami` shows perez.jg22@gmail.com)
- Enoki account at https://enoki.mystenlabs.com (free tier is fine)

## 1. Install the Sui CLI

```sh
brew install sui
# or: curl -LsSf https://github.com/MystenLabs/sui/releases/latest/download/sui-testnet-macos-x86_64.tgz | tar xz -C /usr/local/bin
sui --version        # expect 1.70+
```

## 2. Wire up a testnet env + fund an operator address

```sh
sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
sui client switch --env testnet
sui client new-address ed25519 operator       # creates the operator wallet
sui client switch --address operator
sui client faucet                             # drops 10 SUI from the public faucet
sui client gas                                # confirm you have a gas coin
```

Save the operator's private key for the Worker — exports a 32-byte secret as a base64 string:

```sh
sui keytool export --key-identity $(sui client active-address) --json \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64encode(bytes.fromhex(d['exportedPrivateKey'][2:])).decode())"
```

Copy the base64 output — you'll use it as `SUI_OPERATOR_KEY`.

## 3. Generate an oracle keypair (separate from the operator)

The oracle signs attestations off-chain that the Move contract
verifies on-chain. Private key stays on the Worker; only the pubkey
lands on-chain inside an OracleCap.

```sh
python3 - <<'PY'
import secrets, base64
sk = secrets.token_bytes(32)
# Derive Ed25519 pubkey without requiring cryptography libs:
# use: python3 -m pip install pynacl && run separately.
print("SECRET (base64):", base64.b64encode(sk).decode())
PY
```

Better: use `sui keytool` to generate a key you'll discard the Sui
address for:
```sh
sui keytool generate ed25519 word12
# record the private_key (hex) and public_key (hex)
```

You need the private key as base64 for `ORACLE_PRIVATE_KEY` and the
public key (32 bytes) as a `vector<u8>` when calling `admin::mint_oracle`.

## 4. Publish the Move package

```sh
./scripts/publish-testnet.sh
```

This runs `sui move build` + `sui client publish` and prints the
`packageId` + the wrangler commands you'll need next. Save the
`packageId` — you'll paste it into wrangler.

## 5. Initialize the protocol

After publishing, Sui transfers an `AdminCap` to the publisher (you).
Use it to initialize the `RewardsEngine` + mint an `OracleCap` +
create a `Version` object. Run each as a PTB in the Sui client:

```sh
# Inspect the AdminCap + Version object ids from publish output.
# Then initialize the engine (example values; tune epoch_cap to what you want):

sui client call \
    --package <PACKAGE_ID> \
    --module rewards_engine \
    --function initialize \
    --args <ADMIN_CAP_ID> <TREASURY_CAP_ID> 1000000000000 100000000000 1 \
    --gas-budget 10000000

# Mint the OracleCap with your oracle's public key hex (no 0x):
sui client call \
    --package <PACKAGE_ID> \
    --module admin \
    --function mint_oracle \
    --args <ADMIN_CAP_ID> "0x<ORACLE_PUBKEY_HEX>" \
    --gas-budget 10000000
```

Write down every object id that Sui prints (`RewardsEngine`,
`OracleCap`, `Version`, `AdminCap`).

## 6. Flip the Worker live

```sh
cd cloudflare

echo "<PACKAGE_ID>"      | wrangler secret put SUI_PACKAGE_ID
echo "<REWARDS_ENGINE_ID>" | wrangler secret put SUI_REWARDS_ENGINE_ID
echo "<ORACLE_CAP_ID>"     | wrangler secret put SUI_ORACLE_CAP_ID
echo "<VERSION_OBJECT_ID>" | wrangler secret put SUI_VERSION_OBJECT_ID
echo "<OPERATOR_KEY_B64>"  | wrangler secret put SUI_OPERATOR_KEY
echo "<ORACLE_KEY_B64>"    | wrangler secret put ORACLE_PRIVATE_KEY

wrangler deploy
```

## 7. (Optional but recommended) Enable Enoki zkLogin

```sh
# In https://enoki.mystenlabs.com:
#   1. Create app, set network = testnet
#   2. Add Google OAuth provider (iOS Client ID from Google Cloud)
#   3. Add Apple OAuth provider (Services ID from Apple Developer)
#   4. Copy the SECRET API key

echo "enoki_secret_<yours>" | wrangler secret put ENOKI_SECRET_KEY
wrangler deploy
```

## 8. Verify the pipeline

```sh
curl -sS https://suisport-api.perez-jg22.workers.dev/v1/sui/status | jq
# Expect: configured: true, packageId set, epoch non-null.

# Submit a workout (as the demo athlete):
curl -sS -X POST -H "Content-Type: application/json" \
    "https://suisport-api.perez-jg22.workers.dev/v1/workouts?athleteId=0xdemo_me" \
    -d '{
        "type": "run",
        "startDate": '"$(date +%s)"',
        "durationSeconds": 1800,
        "distanceMeters": 5000,
        "points": 80,
        "title": "Testnet proof"
    }' | jq
# Expect: { pipeline: "executed", txDigest: "0x..." (not "pending_..."), walrusBlobId set }

# See the workout on-chain:
curl -sS https://suisport-api.perez-jg22.workers.dev/v1/workouts/<returned_id>/onchain | jq
# Expect: verified: true, txExplorerUrl set, walrusUrl set.

# Check SWEAT balance grew:
curl -sS https://suisport-api.perez-jg22.workers.dev/v1/sui/balance/0xdemo_me | jq
```

Then open the `txExplorerUrl` in a browser. You should see the
`RewardMinted` event, the `SWEAT` coin transfer, and a new `Workout`
object transferred to the demo athlete.

## 9. Watch the indexer

The cron trigger runs `indexTick` every minute. Tail live:

```sh
wrangler tail
# Look for: "indexed N events" after each cron fires.
```

## 10. iOS testing

- Build the app in Xcode (Cmd+R).
- Sign in with Apple. Apple returns a real `identityToken`.
- If Enoki is configured → backend resolves to your real zkLogin Sui
  address. If not → you get a deterministic mock address.
- Profile → top-right ⋯ → Advanced. You should see your network,
  package id, epoch, and $SWEAT balance.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `status.configured: false` after step 6 | One of the six SUI_* secrets is missing. `wrangler secret list` shows what's set. |
| Workout returns `pipeline: "sui_failed:..."` | Check the error string. Common: `ENonceReused` (hash collision — very rare), `EGlobalCapExceeded` (raise epoch_cap), `EBadSignature` (oracle key mismatch). |
| Workout returns `pipeline: "walrus_upload_failed"` | Public Walrus publisher rate-limits. Wait a minute and retry, or set your own via `WALRUS_PUBLISHER_URL`. |
| `txExplorerUrl` is null even after success | The tx is real but indexer hasn't caught up yet. Wait ~60s. |
| Indexer logs nothing | `wrangler tail` to see if the cron fires. `POST /v1/sui/index` manually triggers a tick. |
| iOS sign-in returns mock | Either Enoki not configured or Apple's id_token verification failed. Backend logs via `wrangler tail`. |

## Cost on testnet

- Sui gas: subsidized by faucet. Each workout submission ≈ 0.003 SUI = $0 (testnet SUI has no value).
- Walrus: testnet publisher is free.
- CF Worker cron (every minute): ~43k invocations/mo on free tier.

Everything on testnet is free to run.
