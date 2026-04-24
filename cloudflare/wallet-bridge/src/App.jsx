import { useEffect, useMemo, useRef, useState } from "react";
import {
    ConnectButton,
    useCurrentAccount,
    useSignPersonalMessage,
    useDisconnectWallet,
} from "@mysten/dapp-kit";

/// Reads `challengeId`, `nonce`, `returnScheme` (defaults to
/// "suisport") from the URL. When the user signs the nonce, we
/// redirect to `<returnScheme>://wallet-connect-callback?…` which
/// iOS intercepts (via ASWebAuthenticationSession callbackURLScheme
/// or a universal link handler).
function useParams() {
    return useMemo(() => {
        const p = new URLSearchParams(window.location.search);
        return {
            challengeId: p.get("challengeId") ?? "",
            nonce: p.get("nonce") ?? "",
            returnScheme: p.get("returnScheme") ?? "suisport",
        };
    }, []);
}

export default function App() {
    const { challengeId, nonce, returnScheme } = useParams();
    const account = useCurrentAccount();
    const { mutate: signPersonalMessage } = useSignPersonalMessage();
    const { mutate: disconnect } = useDisconnectWallet();

    const [status, setStatus] = useState("idle");    // idle | signing | redirecting | error
    const [errMsg, setErrMsg] = useState("");
    const signedForAddress = useRef(null);

    const sign = () => {
        if (!account) return;
        setStatus("signing");
        setErrMsg("");
        signPersonalMessage(
            { message: new TextEncoder().encode(nonce) },
            {
                onSuccess: ({ signature }) => {
                    setStatus("redirecting");
                    const url = new URL(`${returnScheme}://wallet-connect-callback`);
                    url.searchParams.set("challengeId", challengeId);
                    url.searchParams.set("address", account.address);
                    url.searchParams.set("signature", signature);
                    // Defer briefly so the redirecting-state paints.
                    window.setTimeout(() => {
                        window.location.href = url.toString();
                    }, 150);
                },
                onError: (err) => {
                    setStatus("error");
                    setErrMsg(err?.message ?? String(err));
                },
            },
        );
    };

    // Auto-sign the moment a wallet connects. In the canonical flow
    // we're running INSIDE Slush's in-app browser, which auto-injects
    // + auto-connects the user's account — the human just wanted to
    // sign in, they didn't want to tap a second button. Fire once
    // per address; the user can still tap "Sign & continue" if auto
    // fires before they're ready.
    useEffect(() => {
        if (!account || !challengeId || !nonce) return;
        if (signedForAddress.current === account.address) return;
        if (status !== "idle") return;
        signedForAddress.current = account.address;
        sign();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [account?.address, challengeId, nonce]);

    const paramsMissing = !challengeId || !nonce;

    return (
        <div style={styles.page}>
            <div style={styles.card}>
                <h1 style={styles.h1}>Sign in with your Sui wallet</h1>
                <p style={styles.sub}>
                    Your wallet signs a one-time nonce. Your private keys never leave it.
                </p>

                {paramsMissing ? (
                    <div style={styles.errorBox}>
                        Missing challenge. This page should be opened from the SuiSport app.
                    </div>
                ) : (
                    <>
                        <div style={styles.nonceBox}>
                            <div style={styles.nonceLabel}>MESSAGE TO SIGN</div>
                            <div style={styles.nonceText}>{nonce}</div>
                        </div>

                        {!account ? (
                            <div style={styles.connectWrap}>
                                <ConnectButton
                                    connectText="Choose a wallet"
                                    style={styles.connect}
                                />
                                <p style={styles.hint}>
                                    We'll show every Sui wallet installed in this browser.
                                </p>
                            </div>
                        ) : (
                            <div style={styles.signedInBlock}>
                                <div style={styles.addrRow}>
                                    <div style={styles.addrLabel}>Signed in as</div>
                                    <code style={styles.addr}>
                                        {account.address.slice(0, 10)}…{account.address.slice(-6)}
                                    </code>
                                </div>

                                <button
                                    onClick={sign}
                                    disabled={status === "signing" || status === "redirecting"}
                                    style={{
                                        ...styles.primary,
                                        opacity: status === "signing" || status === "redirecting" ? 0.6 : 1,
                                    }}
                                >
                                    {status === "signing"    ? "Signing in your wallet…" :
                                     status === "redirecting" ? "Returning to SuiSport…" :
                                                                "Sign & continue"}
                                </button>

                                <button onClick={() => disconnect()} style={styles.secondary}>
                                    Use a different wallet
                                </button>

                                {status === "error" && (
                                    <div style={styles.errorBox}>
                                        Couldn't sign: {errMsg}
                                    </div>
                                )}
                            </div>
                        )}
                    </>
                )}

                <a
                    href={`${returnScheme}://wallet-connect-callback?challengeId=${encodeURIComponent(challengeId)}&cancel=paste`}
                    style={styles.footerLink}
                >
                    ← Back to SuiSport (I'll paste manually)
                </a>
            </div>
        </div>
    );
}

const suiBlue = "#2172DC";
const suiBlueSoft = "#4C9DF5";

const styles = {
    page: {
        flex: 1, display: "flex", alignItems: "center", justifyContent: "center",
        padding: "24px 20px",
    },
    card: {
        width: "100%", maxWidth: 440,
    },
    h1: {
        fontSize: 24, fontWeight: 700, letterSpacing: "-0.02em", margin: "0 0 8px",
    },
    sub: {
        margin: "0 0 24px", color: "#6a6a6a", fontSize: 14, lineHeight: 1.5,
    },
    nonceBox: {
        background: "rgba(33,114,220,0.06)",
        border: "1px solid rgba(33,114,220,0.18)",
        borderRadius: 12, padding: "12px 14px", marginBottom: 16,
    },
    nonceLabel: {
        fontSize: 10, fontWeight: 700, letterSpacing: "0.14em",
        color: suiBlue, marginBottom: 6,
    },
    nonceText: {
        fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
        fontSize: 12, lineHeight: 1.5, wordBreak: "break-all",
    },
    connectWrap: { marginTop: 8 },
    connect: { width: "100%" },
    hint: {
        fontSize: 12, color: "#6a6a6a", marginTop: 10, textAlign: "center",
    },
    signedInBlock: { display: "flex", flexDirection: "column", gap: 10 },
    addrRow: {
        display: "flex", alignItems: "center", justifyContent: "space-between",
        padding: "10px 12px",
        background: "rgba(0,0,0,0.04)", borderRadius: 10,
    },
    addrLabel: { fontSize: 12, color: "#6a6a6a" },
    addr: {
        fontFamily: "ui-monospace, SF Mono, Menlo, monospace",
        fontSize: 12, fontWeight: 600,
    },
    primary: {
        border: "none", cursor: "pointer",
        padding: "14px 20px", borderRadius: 999, fontSize: 15, fontWeight: 700,
        color: "white",
        background: `linear-gradient(135deg, ${suiBlueSoft} 0%, ${suiBlue} 100%)`,
        boxShadow: "0 4px 16px rgba(33,114,220,0.35)",
    },
    secondary: {
        border: "1px solid rgba(0,0,0,0.12)", cursor: "pointer",
        padding: "10px 16px", borderRadius: 999, fontSize: 13, fontWeight: 600,
        background: "transparent", color: "inherit",
    },
    errorBox: {
        marginTop: 12, padding: "10px 12px", borderRadius: 10,
        background: "rgba(255,0,0,0.08)", color: "#c00", fontSize: 13,
    },
    footerLink: {
        display: "block", textAlign: "center", marginTop: 24,
        color: "#6a6a6a", textDecoration: "underline", fontSize: 12,
    },
};
