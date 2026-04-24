import React from "react";
import ReactDOM from "react-dom/client";
import "@mysten/dapp-kit/dist/index.css";

import {
    SuiClientProvider,
    WalletProvider,
    createNetworkConfig,
} from "@mysten/dapp-kit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { registerSlushWallet } from "@mysten/slush-wallet";

import App from "./App.jsx";

// Register Slush as a discoverable Wallet Standard provider on page
// load so its icon shows up in ConnectButton alongside installed
// extensions + anything else the user has. Origin tells Slush where
// the dApp is — matters for redirect flows.
try {
    registerSlushWallet("SuiSport", {
        origin: window.location.origin,
    });
} catch {
    /* safe to ignore — duplicate registrations noop */
}

const queryClient = new QueryClient({
    defaultOptions: {
        queries: { retry: 2, retryDelay: (n) => Math.min(400 * 2 ** n, 10_000) },
    },
});

// sui-rescue pattern: hardcode the RPC URLs rather than depending on
// getFullnodeUrl, which moved between @mysten/sui versions.
const { networkConfig } = createNetworkConfig({
    testnet: { url: "https://fullnode.testnet.sui.io:443" },
    mainnet: { url: "https://fullnode.mainnet.sui.io:443" },
});

// Default to testnet since that's where our backend's configured.
// The chain doesn't actually matter for signPersonalMessage — only
// for transactions — but stay consistent with the app's config.
ReactDOM.createRoot(document.getElementById("root")).render(
    <React.StrictMode>
        <QueryClientProvider client={queryClient}>
            <SuiClientProvider networks={networkConfig} defaultNetwork="testnet">
                <WalletProvider autoConnect>
                    <App />
                </WalletProvider>
            </SuiClientProvider>
        </QueryClientProvider>
    </React.StrictMode>,
);
