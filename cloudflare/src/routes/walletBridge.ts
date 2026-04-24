import { Hono } from "hono";
import type { Env, Variables } from "../env.js";

export const walletBridge = new Hono<{ Bindings: Env; Variables: Variables }>();

// GET /wallet-connect?challengeId=...&nonce=...&returnScheme=suisport
//
// Self-contained HTML page that runs the Sui Wallet Standard flow and
// hands the signed result back to the native iOS app via a custom URL
// scheme. iOS opens this inside ASWebAuthenticationSession; on
// successful `redirect_to` we capture the address+signature and POST
// them to /v1/auth/wallet/verify.
//
// The wallet detection + signing uses @mysten/slush-wallet + the
// Wallet Standard, loaded via esm.sh so the Worker stays a single
// deploy. When no wallet is reachable in the ephemeral browser
// (common — wallet extensions don't run there), the page renders
// a "no wallet here — paste-back flow" link that re-enters the iOS
// sheet's manual mode.

walletBridge.get("/wallet-connect", (c) => {
    const challengeId = c.req.query("challengeId") ?? "";
    const nonce = c.req.query("nonce") ?? "";
    const returnScheme = c.req.query("returnScheme") ?? "suisport";
    return c.html(page({ challengeId, nonce, returnScheme }));
});

function page(p: { challengeId: string; nonce: string; returnScheme: string }): string {
    const esc = (s: string) => s.replace(/[<>&"'\\]/g, (ch) => `\\${ch}`);
    return `<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>SuiSport — Connect wallet</title>
    <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            padding: 24px 20px;
            font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, sans-serif;
            background: #fafafa;
            color: #111;
        }
        @media (prefers-color-scheme: dark) {
            body { background: #0a0a0a; color: #f0f0f0; }
            .card { background: #141414 !important; border-color: #222 !important; }
            .nonce { background: #0f0f0f !important; }
            button.primary { box-shadow: 0 4px 18px rgba(33, 114, 220, .45) !important; }
        }
        h1 { margin: 0 0 4px; font-size: 22px; font-weight: 700; letter-spacing: -0.01em; }
        .sub { color: #6a6a6a; margin: 0 0 24px; }
        .card {
            background: white; border: 1px solid #e5e5e5;
            border-radius: 14px; padding: 16px 18px; margin: 14px 0;
        }
        .step { display: flex; gap: 10px; align-items: flex-start; }
        .step-num {
            width: 22px; height: 22px; border-radius: 11px;
            background: #2172DC; color: white;
            display: inline-flex; align-items: center; justify-content: center;
            font-size: 12px; font-weight: 700; flex-shrink: 0; margin-top: 1px;
        }
        .nonce {
            font-family: ui-monospace, "SF Mono", Menlo, monospace;
            font-size: 13px; background: #f4f6fa; padding: 10px 12px;
            border-radius: 8px; word-break: break-all; margin-top: 10px;
        }
        button {
            font: inherit; border: none; cursor: pointer;
            padding: 12px 18px; border-radius: 12px; font-weight: 600;
            transition: transform 120ms, box-shadow 120ms;
            width: 100%; margin-top: 12px;
        }
        button:active { transform: scale(0.98); }
        button.primary {
            color: white;
            background: linear-gradient(135deg, #4C9DF5 0%, #2172DC 100%);
            box-shadow: 0 4px 14px rgba(33, 114, 220, .35);
        }
        button.secondary {
            background: #ececec; color: #111;
        }
        @media (prefers-color-scheme: dark) {
            button.secondary { background: #222; color: #f0f0f0; }
        }
        .wallets { margin-top: 12px; display: grid; gap: 8px; }
        .wallet {
            display: flex; align-items: center; gap: 10px;
            padding: 12px 14px; border-radius: 12px;
            background: #f4f6fa; border: 1px solid transparent;
            cursor: pointer;
        }
        .wallet:hover { border-color: #2172DC; }
        .wallet img { width: 28px; height: 28px; border-radius: 6px; }
        .status {
            margin-top: 14px; padding: 12px 14px; border-radius: 10px;
            font-size: 13px;
        }
        .status.error { background: #fde8e8; color: #b00; }
        .status.info { background: #e8f0fd; color: #2172DC; }
        @media (prefers-color-scheme: dark) {
            .status.error { background: #3b1e1e; color: #f88; }
            .status.info { background: #162437; color: #7ebaff; }
        }
        .footer-link {
            margin-top: 22px; display: block; text-align: center;
            font-size: 13px; color: #6a6a6a; text-decoration: underline;
        }
    </style>
</head>
<body>
    <h1>Sign in with your Sui wallet</h1>
    <p class="sub">Your wallet signs a one-time nonce. The signature goes to SuiSport — your private keys never leave your wallet.</p>

    <div class="card">
        <div class="step">
            <div class="step-num">1</div>
            <div style="flex:1">
                <div style="font-weight:600">Message to sign</div>
                <div class="nonce" id="nonce-display">${esc(p.nonce)}</div>
            </div>
        </div>
    </div>

    <div class="card">
        <div class="step">
            <div class="step-num">2</div>
            <div style="flex:1">
                <div style="font-weight:600">Pick a wallet</div>
                <div id="wallet-list" class="wallets"></div>
                <div id="no-wallet" class="status info" style="display:none">
                    No Sui wallets detected in this browser. If you're on a device with Slush or another Sui wallet installed, open this page inside that wallet's dApp browser.
                </div>
            </div>
        </div>
    </div>

    <div id="status"></div>

    <a class="footer-link" id="manual-link" href="#">Go back — I'll paste the signature manually</a>

    <script type="module">
        // We load the Sui + Slush packages via esm.sh. Worker stays
        // a single deploy; no bundler in this loop.
        const slushPromise = import("https://esm.sh/@mysten/slush-wallet@latest?bundle");
        const walletStandardPromise = import("https://esm.sh/@mysten/wallet-standard@latest?bundle");

        const params = new URLSearchParams(window.location.search);
        const challengeId = params.get("challengeId") ?? "";
        const nonce = params.get("nonce") ?? "";
        const returnScheme = params.get("returnScheme") ?? "suisport";

        const statusEl = document.getElementById("status");
        const listEl = document.getElementById("wallet-list");
        const noWalletEl = document.getElementById("no-wallet");
        const manualLink = document.getElementById("manual-link");

        manualLink.addEventListener("click", (e) => {
            e.preventDefault();
            location.href = \`\${returnScheme}://wallet-connect-callback?challengeId=\${encodeURIComponent(challengeId)}&cancel=paste\`;
        });

        function setStatus(kind, msg) {
            statusEl.innerHTML = \`<div class="status \${kind}">\${msg}</div>\`;
        }

        try {
            const { registerSlushWallet } = await slushPromise;
            // Register Slush as a discoverable wallet on this page so
            // the Wallet Standard sees it alongside any already-installed
            // wallets (extensions, in-app browsers).
            try {
                registerSlushWallet?.("SuiSport", { origin: location.origin });
            } catch { /* non-fatal */ }

            const ws = await walletStandardPromise;
            const wallets = ws.getWallets().get().filter(w =>
                w.chains.some(c => c.startsWith("sui:"))
            );

            if (!wallets.length) {
                noWalletEl.style.display = "block";
                return;
            }

            wallets.forEach(w => {
                const b = document.createElement("button");
                b.className = "wallet";
                b.innerHTML = \`<img src="\${w.icon}" alt="" /> <span>\${w.name}</span>\`;
                b.addEventListener("click", () => connectAndSign(w));
                listEl.appendChild(b);
            });

            setStatus("info", "Pick a wallet above to continue.");
        } catch (err) {
            setStatus("error", "Failed to load wallet SDK — use the manual paste path. (" + (err?.message ?? err) + ")");
        }

        async function connectAndSign(wallet) {
            try {
                setStatus("info", \`Connecting to \${wallet.name}…\`);
                const connectFeature = wallet.features["standard:connect"];
                const { accounts } = await connectFeature.connect();
                const account = accounts?.[0];
                if (!account) throw new Error("Wallet returned no account");

                setStatus("info", \`Asking \${wallet.name} to sign…\`);
                const signFeature = wallet.features["sui:signPersonalMessage"];
                if (!signFeature) throw new Error(wallet.name + " can't sign personal messages");
                const { signature } = await signFeature.signPersonalMessage({
                    message: new TextEncoder().encode(nonce),
                    account,
                });

                setStatus("info", "Signed ✓ — redirecting back to SuiSport…");
                const cb = new URL(\`\${returnScheme}://wallet-connect-callback\`);
                cb.searchParams.set("challengeId", challengeId);
                cb.searchParams.set("address", account.address);
                cb.searchParams.set("signature", signature);
                location.href = cb.toString();
            } catch (err) {
                const msg = err?.message ?? String(err);
                setStatus("error", "Sign failed: " + msg);
            }
        }
    </script>
</body>
</html>`;
}
