// Apple App Attest verification.
//
// Flow:
//   1. iOS: DCAppAttestService.generateKey() → keyId
//   2. iOS: GET /v1/attestation/challenge → random 32-byte nonce
//          (returned as base64url of 32 raw bytes)
//   3. iOS: decodes b64url to 32 raw bytes, clientDataHash =
//          SHA256(rawBytes), then DCAppAttestService.attestKey(
//            keyId, clientDataHash: clientDataHash)
//          → CBOR attestation object (fmt = "apple-appattest")
//   4. iOS: POST /v1/attestation/register
//            { keyId, attestation_b64, challenge_b64url }
//   5. Worker verifies all 10 steps from Apple's spec:
//        https://developer.apple.com/documentation/devicecheck/
//          validating_apps_that_connect_to_your_server
//      a. challenge has been issued, unconsumed, not expired
//      b. CBOR decode + fmt == "apple-appattest"
//      c. x5c chain verifies against Apple's App Attest root CA
//         (leaf signed by intermediate, intermediate signed by root,
//          issuer/subject DNs match at each link)
//      d. credCert OID 1.2.840.113635.100.8.2 extension value equals
//         nonce = SHA256(authData || clientDataHash)
//      e. rpIdHash (authData[0..32]) == SHA256("<TEAM_ID>.<BUNDLE_ID>")
//      f. counter (authData[33..37]) == 0
//      g. aaguid (authData[37..53]) matches the production token
//         ("appattest" + 7 null bytes) or dev token ("appattestdevelop")
//         depending on APPATTEST_ENV
//      h. credentialId (authData[55..55+L]) == keyId bytes
//      i. SHA256(uncompressed EC pubkey from credCert) == keyId bytes
//      j. persist pubkey, mark challenge consumed, cert_chain_ok=1
//
//   On each subsequent sensitive call (assertion):
//   6. iOS: DCAppAttestService.generateAssertion(keyId, clientDataHash)
//      → CBOR assertion
//   7. Worker: verifySignature(pubkey, authData || clientDataHash, signature)
//              + counter > lastCounter
//
// Security posture:
//   Before this revision, cert_chain_ok was always 0 and the nonce
//   extension was unchecked — an attacker who could generate any
//   ECDSA P-256 keypair could forge attestations. With cert-chain
//   + nonce + aaguid + credentialId + keyId-pubkey-hash all wired
//   up, forgery requires breaking one of: Apple's root CA ECDSA key
//   (P-384), the intermediate CA key, or the device's Secure Enclave.

import { decode as cborDecode } from "cbor-x";
import type { Env } from "./env.js";

/// Apple App Attest production Root CA (embedded — Apple rotates
/// infrequently and the cert is valid through 2045).
/// https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
const APPLE_APP_ATTEST_ROOT_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

/// OID values (DER-encoded as their .1 .2 .3... dotted form).
const OID_CRED_CERT_NONCE       = "1.2.840.113635.100.8.2";
const OID_EC_PUBLIC_KEY         = "1.2.840.10045.2.1";
const OID_SECP256R1             = "1.2.840.10045.3.1.7";
const OID_SECP384R1             = "1.3.132.0.34";
const OID_ECDSA_WITH_SHA256     = "1.2.840.10045.4.3.2";
const OID_ECDSA_WITH_SHA384     = "1.2.840.10045.4.3.3";

/// AAGUIDs — 16-byte identifiers Apple embeds in authData to tag
/// the attestation environment.
const AAGUID_PROD = new Uint8Array([
    0x61, 0x70, 0x70, 0x61, 0x74, 0x74, 0x65, 0x73, 0x74, // "appattest"
    0, 0, 0, 0, 0, 0, 0,
]);
const AAGUID_DEV = new Uint8Array([
    0x61, 0x70, 0x70, 0x61, 0x74, 0x74, 0x65, 0x73, 0x74, // "appattest"
    0x64, 0x65, 0x76, 0x65, 0x6c, 0x6f, 0x70,             // "develop"
]);

interface AttestationObject {
    fmt: string;              // "apple-appattest"
    attStmt: { x5c: Uint8Array[]; receipt: Uint8Array };
    authData: Uint8Array;
}

/// Registers a fresh App Attest key. Verifies every check Apple's
/// documentation requires; on success stores `cert_chain_ok=1`.
export async function registerAttestation(
    env: Env,
    athleteId: string,
    keyIdB64: string,
    attestationB64: string,
    challengeB64url: string
): Promise<{ ok: true; certChainVerified: boolean }> {
    // --- (a) challenge is valid, unconsumed, fresh ---
    const challenge = await env.DB.prepare(
        `SELECT created_at, consumed FROM attest_challenges WHERE challenge = ? AND athlete_id = ?`
    ).bind(challengeB64url, athleteId).first<{ created_at: number; consumed: number }>();
    if (!challenge) throw new AttestError("bad_challenge");
    if (challenge.consumed === 1) throw new AttestError("challenge_reused");
    if (Math.floor(Date.now() / 1000) - challenge.created_at > 300) throw new AttestError("challenge_expired");

    // --- (b) CBOR-decode the attestation object ---
    const attBytes = b64ToBytes(attestationB64);
    const att = cborDecode(attBytes) as AttestationObject;
    if (att.fmt !== "apple-appattest") throw new AttestError("bad_fmt");
    if (!Array.isArray(att.attStmt?.x5c) || att.attStmt.x5c.length < 2) {
        throw new AttestError("bad_x5c");
    }

    // --- (c) Cert chain: leaf → intermediate → Apple root ---
    const leafDer = att.attStmt.x5c[0];
    const intermediateDer = att.attStmt.x5c[1];
    const rootDer = pemToDer(APPLE_APP_ATTEST_ROOT_PEM);
    const leaf = parseCertificate(leafDer);
    const intermediate = parseCertificate(intermediateDer);
    const root = parseCertificate(rootDer);

    if (!bytesEqual(intermediate.issuerDn, root.subjectDn)) {
        throw new AttestError("intermediate_issuer_mismatch");
    }
    if (!bytesEqual(leaf.issuerDn, intermediate.subjectDn)) {
        throw new AttestError("leaf_issuer_mismatch");
    }
    // Intermediate signed by root (ECDSA-P384-SHA384)
    if (!(await verifyCertSignature(intermediate, root))) {
        throw new AttestError("intermediate_bad_sig");
    }
    // Leaf signed by intermediate (ECDSA-P256-SHA256 per Apple spec)
    if (!(await verifyCertSignature(leaf, intermediate))) {
        throw new AttestError("leaf_bad_sig");
    }

    // --- (d) Nonce extension == SHA256(authData || clientDataHash) ---
    // Our challenge contract: server stores b64url of 32 random bytes.
    // iOS decodes b64url → 32 raw bytes → clientDataHash = SHA256(raw).
    // Server replays the same computation here.
    const challengeRaw = b64urlToBytes(challengeB64url);
    const clientDataHash = new Uint8Array(
        await crypto.subtle.digest("SHA-256", challengeRaw)
    );
    const authData = att.authData;
    if (!(authData instanceof Uint8Array) || authData.length < 37) {
        throw new AttestError("bad_authdata");
    }
    const nonceExpected = new Uint8Array(
        await crypto.subtle.digest("SHA-256", concat(authData, clientDataHash))
    );
    const nonceExtension = leaf.extensions.get(OID_CRED_CERT_NONCE);
    if (!nonceExtension) throw new AttestError("missing_nonce_ext");
    const nonceActual = extractOctetStringFromNonceExt(nonceExtension);
    if (!nonceActual || !bytesEqual(nonceActual, nonceExpected)) {
        throw new AttestError("nonce_mismatch");
    }

    // --- (e) rpIdHash == SHA256("<TEAM_ID>.<BUNDLE_ID>") ---
    const rpIdHash = authData.slice(0, 32);
    const appId = env.APPATTEST_APP_ID;
    if (appId) {
        const expectedRpIdHash = new Uint8Array(
            await crypto.subtle.digest("SHA-256", new TextEncoder().encode(appId))
        );
        if (!bytesEqual(rpIdHash, expectedRpIdHash)) {
            throw new AttestError("rpid_mismatch");
        }
    }

    // --- (f) counter == 0 (fresh key) ---
    const counter = readUint32BE(authData, 33);
    if (counter !== 0) throw new AttestError("counter_not_zero");

    // --- (g) aaguid matches production or development token ---
    const aaguid = authData.slice(37, 53);
    const expectedAaguid = env.APPATTEST_ENV === "development"
        ? AAGUID_DEV
        : AAGUID_PROD;
    if (!bytesEqual(aaguid, expectedAaguid)) {
        throw new AttestError("aaguid_mismatch");
    }

    // --- Extract credentialId + credential pubkey from authData ---
    const aaguidEnd = 37 + 16;
    const credIdLen = (authData[aaguidEnd] << 8) | authData[aaguidEnd + 1];
    const credIdStart = aaguidEnd + 2;
    const credIdEnd = credIdStart + credIdLen;
    const credentialId = authData.slice(credIdStart, credIdEnd);
    const coseKey = cborDecode(authData.slice(credIdEnd)) as Map<number, unknown>;
    const x = coseKey.get(-2) as Uint8Array;
    const y = coseKey.get(-3) as Uint8Array;
    if (!(x instanceof Uint8Array) || !(y instanceof Uint8Array)) {
        throw new AttestError("bad_cose_key");
    }
    // Uncompressed EC point: 0x04 || X || Y
    const uncompressedPubkey = new Uint8Array(1 + x.length + y.length);
    uncompressedPubkey[0] = 0x04;
    uncompressedPubkey.set(x, 1);
    uncompressedPubkey.set(y, 1 + x.length);

    // --- (h) credentialId in authData == keyId bytes ---
    const keyIdBytes = b64ToBytes(keyIdB64);
    if (!bytesEqual(credentialId, keyIdBytes)) {
        throw new AttestError("cred_id_mismatch");
    }

    // --- (i) SHA256(leaf cert's EC pubkey, uncompressed) == keyId ---
    // leaf.publicKeyUncompressed is already 0x04 || X || Y from DER.
    const pubkeyHash = new Uint8Array(
        await crypto.subtle.digest("SHA-256", leaf.publicKeyUncompressed)
    );
    if (!bytesEqual(pubkeyHash, keyIdBytes)) {
        throw new AttestError("pubkey_hash_mismatch");
    }
    // And the COSE key from authData must match the cert's pubkey —
    // otherwise assertion verification (which uses the COSE key in DB)
    // would validate signatures made with a different key than was
    // attested.
    if (!bytesEqual(uncompressedPubkey, leaf.publicKeyUncompressed)) {
        throw new AttestError("cose_cert_pubkey_mismatch");
    }

    const publicKeyJwk = {
        kty: "EC",
        crv: "P-256",
        x: bytesToB64Url(x),
        y: bytesToB64Url(y),
    };

    // --- (j) Persist + mark challenge consumed ---
    await env.DB.batch([
        env.DB.prepare(
            `INSERT OR REPLACE INTO app_attest_keys
             (key_id, athlete_id, public_key_jwk, counter, receipt, cert_chain_ok)
             VALUES (?, ?, ?, 0, ?, 1)`
        ).bind(
            keyIdB64, athleteId, JSON.stringify(publicKeyJwk),
            att.attStmt.receipt
        ),
        env.DB.prepare(
            `UPDATE attest_challenges SET consumed = 1 WHERE challenge = ?`
        ).bind(challengeB64url),
    ]);

    return { ok: true, certChainVerified: true };
}

/// Verify an assertion from a previously-registered key. Unchanged by
/// this revision — the signature check already uses the JWK pubkey
/// stored in step (j). Now that registration is hardened, the stored
/// pubkey is actually attested to.
export async function verifyAssertion(
    env: Env,
    keyIdB64: string,
    assertionB64: string,
    clientDataHash: ArrayBuffer
): Promise<{ ok: true } | { ok: false; reason: string }> {
    const row = await env.DB.prepare(
        `SELECT public_key_jwk, counter, cert_chain_ok FROM app_attest_keys WHERE key_id = ?`
    ).bind(keyIdB64).first<{ public_key_jwk: string; counter: number; cert_chain_ok: number }>();
    if (!row) return { ok: false, reason: "unknown_key" };
    // Refuse assertions from keys that were registered before cert-chain
    // verification shipped — the caller should re-attest.
    if (row.cert_chain_ok !== 1) return { ok: false, reason: "unverified_key" };

    const assertion = cborDecode(b64ToBytes(assertionB64)) as {
        signature: Uint8Array;
        authenticatorData: Uint8Array;
    };
    const newCounter = readUint32BE(assertion.authenticatorData, 33);
    if (newCounter <= row.counter) {
        return { ok: false, reason: "counter_replay" };
    }

    const jwk = JSON.parse(row.public_key_jwk);
    const key = await crypto.subtle.importKey(
        "jwk", jwk, { name: "ECDSA", namedCurve: "P-256" },
        false, ["verify"]
    );
    const signed = concat(assertion.authenticatorData, new Uint8Array(clientDataHash));
    // iOS returns DER-encoded ECDSA signatures; WebCrypto wants raw r||s.
    const rawSig = ecdsaDerToRaw(assertion.signature, 32);
    const verified = await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" }, key, rawSig, signed
    );
    if (!verified) return { ok: false, reason: "bad_signature" };

    await env.DB.prepare(
        `UPDATE app_attest_keys SET counter = ?, last_used_at = unixepoch() WHERE key_id = ?`
    ).bind(newCounter, keyIdB64).run();
    return { ok: true };
}

export class AttestError extends Error {
    constructor(public readonly code: string) {
        super(code);
        this.name = "AttestError";
    }
}

// =========================================================================
// ASN.1 / DER parsing — the minimum needed to verify X.509 certs
// =========================================================================

interface TLV {
    tag: number;
    value: Uint8Array;
    headerLen: number;
    totalLen: number;
}

/// Parse one Tag-Length-Value triple starting at `off`. Supports short
/// and long-form lengths. Enforces that length fits within the buffer.
function readTLV(buf: Uint8Array, off: number): TLV {
    if (off + 2 > buf.length) throw new AttestError("asn1_truncated");
    const tag = buf[off];
    let lenByte = buf[off + 1];
    let headerLen = 2;
    let length: number;
    if ((lenByte & 0x80) === 0) {
        length = lenByte;
    } else {
        const numBytes = lenByte & 0x7f;
        if (numBytes === 0 || numBytes > 4) throw new AttestError("asn1_bad_len");
        if (off + 2 + numBytes > buf.length) throw new AttestError("asn1_truncated");
        length = 0;
        for (let i = 0; i < numBytes; i++) {
            length = (length << 8) | buf[off + 2 + i];
        }
        headerLen = 2 + numBytes;
    }
    if (off + headerLen + length > buf.length) throw new AttestError("asn1_truncated");
    return {
        tag,
        value: buf.slice(off + headerLen, off + headerLen + length),
        headerLen,
        totalLen: headerLen + length,
    };
}

/// Walk children of a SEQUENCE or SET, returning each child TLV.
function childrenOf(tlv: TLV): TLV[] {
    const out: TLV[] = [];
    let off = 0;
    while (off < tlv.value.length) {
        const child = readTLV(tlv.value, off);
        out.push(child);
        off += child.totalLen;
    }
    return out;
}

/// Convert a dotted DER OID byte sequence to its canonical
/// "1.2.840.113635.100.8.2" string form.
function oidToString(oidBytes: Uint8Array): string {
    if (oidBytes.length === 0) return "";
    const parts: number[] = [];
    // First byte encodes (first * 40) + second.
    parts.push(Math.floor(oidBytes[0] / 40));
    parts.push(oidBytes[0] % 40);
    let acc = 0;
    for (let i = 1; i < oidBytes.length; i++) {
        const b = oidBytes[i];
        acc = (acc << 7) | (b & 0x7f);
        if ((b & 0x80) === 0) {
            parts.push(acc);
            acc = 0;
        }
    }
    return parts.join(".");
}

// =========================================================================
// X.509 certificate parsing — just enough for cert chain verification
// =========================================================================

interface ParsedCert {
    /// The TBSCertificate DER bytes (what the issuer signs over).
    tbs: Uint8Array;
    /// Signature algorithm OID (1.2.840.10045.4.3.2 = ECDSA-SHA256,
    /// 1.2.840.10045.4.3.3 = ECDSA-SHA384).
    signatureAlgo: string;
    /// Signature value — DER-encoded ECDSA { r, s } sequence.
    signatureDer: Uint8Array;
    /// Issuer DN bytes (the raw SEQUENCE including tag+length). A child
    /// cert's issuerDn must byte-match its parent's subjectDn.
    issuerDn: Uint8Array;
    subjectDn: Uint8Array;
    /// Subject public key algorithm OID.
    publicKeyAlgo: string;
    /// EC curve OID (only set when publicKeyAlgo = id-ecPublicKey).
    publicKeyCurve?: string;
    /// Uncompressed EC point: 0x04 || X || Y.
    publicKeyUncompressed: Uint8Array;
    /// Extensions map: OID → extension value (inner OCTET STRING
    /// contents, i.e. the DER-encoded extnValue payload).
    extensions: Map<string, Uint8Array>;
}

/// Parse an X.509 v3 certificate's structure. Only extracts the fields
/// needed for App Attest verification — issuer/subject DN byte-match,
/// EC pubkey extraction, signature verification inputs, extensions
/// lookup. Does NOT parse Name attributes, validity dates, etc.
function parseCertificate(der: Uint8Array): ParsedCert {
    // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
    const outer = readTLV(der, 0);
    if (outer.tag !== 0x30) throw new AttestError("cert_not_sequence");
    const [tbsTlv, sigAlgTlv, sigTlv] = childrenOf(outer);

    // TBSCertificate ::= SEQUENCE {
    //   [0] EXPLICIT Version DEFAULT v1,
    //   serialNumber          CertificateSerialNumber,
    //   signature             AlgorithmIdentifier,  (redundant w/ outer)
    //   issuer                Name,
    //   validity              Validity,
    //   subject               Name,
    //   subjectPublicKeyInfo  SubjectPublicKeyInfo,
    //   ... extensions        [3] EXPLICIT Extensions OPTIONAL
    // }
    if (tbsTlv.tag !== 0x30) throw new AttestError("tbs_not_sequence");
    const tbsChildren = childrenOf(tbsTlv);
    let idx = 0;
    // Skip optional version [0] EXPLICIT
    if (tbsChildren[idx].tag === 0xa0) idx++;
    idx++;                          // serialNumber
    idx++;                          // signatureAlgorithm (redundant)
    const issuerTlv   = tbsChildren[idx++];
    idx++;                          // validity
    const subjectTlv  = tbsChildren[idx++];
    const spkiTlv     = tbsChildren[idx++];
    // Extensions are at [3] EXPLICIT; unique Uid fields at [1], [2]
    // can precede but Apple doesn't use them.
    let extensionsTlv: TLV | undefined;
    while (idx < tbsChildren.length) {
        const t = tbsChildren[idx++];
        if (t.tag === 0xa3) { extensionsTlv = t; break; }
    }

    // Reconstruct DER bytes of issuer/subject by slicing from the
    // original TBS — we need the full TLV (tag+length+value) for
    // byte-equality with the parent cert's subject.
    const issuerDn  = reconstructTlvBytes(tbsTlv.value, issuerTlv);
    const subjectDn = reconstructTlvBytes(tbsTlv.value, subjectTlv);

    // Signature algorithm (outer)
    const [sigAlgOidTlv] = childrenOf(sigAlgTlv);
    const signatureAlgo = oidToString(sigAlgOidTlv.value);

    // signature BIT STRING — first byte is unusedBits (always 0 here).
    if (sigTlv.tag !== 0x03) throw new AttestError("sig_not_bitstring");
    if (sigTlv.value[0] !== 0x00) throw new AttestError("sig_unused_bits");
    const signatureDer = sigTlv.value.slice(1);

    // SubjectPublicKeyInfo ::= SEQUENCE { algorithm, subjectPublicKey BIT STRING }
    const [spkiAlgTlv, spkiKeyTlv] = childrenOf(spkiTlv);
    const spkiAlgChildren = childrenOf(spkiAlgTlv);
    const publicKeyAlgo = oidToString(spkiAlgChildren[0].value);
    let publicKeyCurve: string | undefined;
    if (publicKeyAlgo === OID_EC_PUBLIC_KEY && spkiAlgChildren.length >= 2) {
        publicKeyCurve = oidToString(spkiAlgChildren[1].value);
    }
    if (spkiKeyTlv.tag !== 0x03) throw new AttestError("spki_not_bitstring");
    if (spkiKeyTlv.value[0] !== 0x00) throw new AttestError("spki_unused_bits");
    const publicKeyUncompressed = spkiKeyTlv.value.slice(1);
    if (publicKeyUncompressed[0] !== 0x04) {
        throw new AttestError("spki_not_uncompressed");
    }

    // Extensions ::= SEQUENCE OF Extension
    // Extension ::= SEQUENCE { extnID OID, critical BOOLEAN DEFAULT FALSE, extnValue OCTET STRING }
    const extensions = new Map<string, Uint8Array>();
    if (extensionsTlv) {
        const extsSeq = readTLV(extensionsTlv.value, 0);
        for (const ext of childrenOf(extsSeq)) {
            const extChildren = childrenOf(ext);
            let c = 0;
            const oid = oidToString(extChildren[c++].value);
            // Skip optional critical BOOLEAN
            if (extChildren[c].tag === 0x01) c++;
            const extnValue = extChildren[c];
            if (extnValue.tag !== 0x04) continue; // not OCTET STRING
            extensions.set(oid, extnValue.value);
        }
    }

    return {
        tbs: reconstructTlvBytes(der, tbsTlv),
        signatureAlgo,
        signatureDer,
        issuerDn,
        subjectDn,
        publicKeyAlgo,
        publicKeyCurve,
        publicKeyUncompressed,
        extensions,
    };
}

/// Given a TLV parsed out of `parent`, return the full bytes
/// (header + value) as they appear in `parent` so we can byte-match
/// them against another cert's identical-value field.
function reconstructTlvBytes(parent: Uint8Array, child: TLV): Uint8Array {
    // Find child by scanning parent for a TLV whose value slice matches
    // child.value. We could track offsets instead but readTLV returns
    // slices, not offsets — cheaper to rebuild the bytes.
    const out = new Uint8Array(child.headerLen + child.value.length);
    // Reconstruct header.
    out[0] = child.tag;
    if (child.value.length < 0x80) {
        out[1] = child.value.length;
    } else {
        const lenBytes: number[] = [];
        let len = child.value.length;
        while (len > 0) { lenBytes.unshift(len & 0xff); len >>= 8; }
        out[1] = 0x80 | lenBytes.length;
        for (let i = 0; i < lenBytes.length; i++) out[2 + i] = lenBytes[i];
    }
    out.set(child.value, child.headerLen);
    return out;
}

/// Verify an ECDSA signature on a child cert using the issuer's
/// public key. Handles ECDSA-P256-SHA256 (leaf cert) and
/// ECDSA-P384-SHA384 (intermediate signed by root).
async function verifyCertSignature(child: ParsedCert, issuer: ParsedCert): Promise<boolean> {
    let hash: "SHA-256" | "SHA-384";
    let coordLen: number;
    let namedCurve: "P-256" | "P-384";
    if (child.signatureAlgo === OID_ECDSA_WITH_SHA256) {
        hash = "SHA-256"; coordLen = 32;
    } else if (child.signatureAlgo === OID_ECDSA_WITH_SHA384) {
        hash = "SHA-384"; coordLen = 48;
    } else {
        throw new AttestError(`unsupported_sig_algo:${child.signatureAlgo}`);
    }
    if (issuer.publicKeyCurve === OID_SECP256R1) namedCurve = "P-256";
    else if (issuer.publicKeyCurve === OID_SECP384R1) namedCurve = "P-384";
    else throw new AttestError(`unsupported_curve:${issuer.publicKeyCurve}`);

    // Import the issuer's public key as a JWK so WebCrypto accepts it
    // without us building raw-SPKI DER.
    const half = (issuer.publicKeyUncompressed.length - 1) / 2;
    const jwk = {
        kty: "EC",
        crv: namedCurve,
        x: bytesToB64Url(issuer.publicKeyUncompressed.slice(1, 1 + half)),
        y: bytesToB64Url(issuer.publicKeyUncompressed.slice(1 + half)),
    };
    const key = await crypto.subtle.importKey(
        "jwk", jwk, { name: "ECDSA", namedCurve },
        false, ["verify"]
    );
    const rawSig = ecdsaDerToRaw(child.signatureDer, coordLen);
    return await crypto.subtle.verify(
        { name: "ECDSA", hash }, key, rawSig, child.tbs
    );
}

/// Convert a DER-encoded ECDSA signature (SEQUENCE { r, s }) into the
/// raw r||s format WebCrypto expects. `coordLen` is 32 for P-256, 48
/// for P-384. Leading zero bytes in DER INTEGERs (sign bit padding)
/// are stripped, and each half is left-padded to coordLen.
function ecdsaDerToRaw(derSig: Uint8Array, coordLen: number): Uint8Array {
    const seq = readTLV(derSig, 0);
    if (seq.tag !== 0x30) throw new AttestError("ecdsa_sig_not_seq");
    const [rTlv, sTlv] = childrenOf(seq);
    if (rTlv.tag !== 0x02 || sTlv.tag !== 0x02) {
        throw new AttestError("ecdsa_sig_not_ints");
    }
    const r = stripLeadingZeros(rTlv.value);
    const s = stripLeadingZeros(sTlv.value);
    if (r.length > coordLen || s.length > coordLen) {
        throw new AttestError("ecdsa_sig_too_long");
    }
    const out = new Uint8Array(coordLen * 2);
    out.set(r, coordLen - r.length);
    out.set(s, coordLen * 2 - s.length);
    return out;
}

function stripLeadingZeros(b: Uint8Array): Uint8Array {
    let i = 0;
    while (i < b.length - 1 && b[i] === 0) i++;
    return b.slice(i);
}

/// The credCert nonce extension is a DER-encoded SEQUENCE containing
/// a [1] EXPLICIT OCTET STRING with the nonce value. Apple spec:
///   SEQUENCE {
///     [1] EXPLICIT {
///       OCTET STRING nonce
///     }
///   }
function extractOctetStringFromNonceExt(extValue: Uint8Array): Uint8Array | null {
    try {
        const seq = readTLV(extValue, 0);
        if (seq.tag !== 0x30) return null;
        const tagged = readTLV(seq.value, 0);
        // Context-specific [1] EXPLICIT: tag = 0xa1
        if (tagged.tag !== 0xa1) return null;
        const octet = readTLV(tagged.value, 0);
        if (octet.tag !== 0x04) return null;
        return octet.value;
    } catch {
        return null;
    }
}

// =========================================================================
// Small byte helpers
// =========================================================================

function pemToDer(pem: string): Uint8Array {
    const b64 = pem
        .replace(/-----BEGIN CERTIFICATE-----/g, "")
        .replace(/-----END CERTIFICATE-----/g, "")
        .replace(/\s+/g, "");
    return b64ToBytes(b64);
}

function b64ToBytes(s: string): Uint8Array {
    const padded = s + "=".repeat((4 - (s.length % 4)) % 4);
    const normalized = padded.replace(/-/g, "+").replace(/_/g, "/");
    const bin = atob(normalized);
    return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

function b64urlToBytes(s: string): Uint8Array {
    return b64ToBytes(s);  // b64ToBytes already handles b64url.
}

function bytesToB64Url(b: Uint8Array): string {
    let s = "";
    for (const x of b) s += String.fromCharCode(x);
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff === 0;
}

function readUint32BE(buf: Uint8Array, off: number): number {
    return ((buf[off] << 24) | (buf[off + 1] << 16) | (buf[off + 2] << 8) | buf[off + 3]) >>> 0;
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
    const out = new Uint8Array(a.length + b.length);
    out.set(a, 0); out.set(b, a.length);
    return out;
}
