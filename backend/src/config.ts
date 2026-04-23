import "dotenv/config";

function env(name: string, required = true): string {
  const v = process.env[name];
  if (required && (!v || v.length === 0)) {
    throw new Error(`Missing env var ${name}`);
  }
  return v ?? "";
}

export const config = {
  port: Number(process.env.PORT ?? 8787),
  env: process.env.NODE_ENV ?? "development",
  enoki: {
    apiKey: env("ENOKI_API_KEY", false),
  },
  sui: {
    network: env("SUI_NETWORK", false) || "testnet",
    packageId: env("SUI_PACKAGE_ID", false),
    rewardsEngineId: env("SUI_REWARDS_ENGINE_ID", false),
    oracleCapId: env("SUI_ORACLE_CAP_ID", false),
    versionObjectId: env("SUI_VERSION_OBJECT_ID", false),
  },
  oracle: {
    privateKeyHex: env("ORACLE_PRIVATE_KEY_HEX", false),
    publicKeyHex: env("ORACLE_PUBLIC_KEY_HEX", false),
  },
  apple: {
    appId: env("APPLE_APP_ID", false),
    teamId: env("APPLE_TEAM_ID", false),
  },
  walrus: {
    publisherUrl: env("WALRUS_PUBLISHER_URL", false),
    aggregatorUrl: env("WALRUS_AGGREGATOR_URL", false),
  },
} as const;
