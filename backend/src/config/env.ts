import dotenv from "dotenv";

dotenv.config();

const developmentCorsOrigins = [
  "http://localhost:3000",
  "http://127.0.0.1:3000"
] as const;

const required = (key: string): string => {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
};

const integer = (key: string, fallback: number): number => {
  const value = Number(process.env[key] ?? fallback);
  return Number.isInteger(value) && value > 0 ? value : fallback;
};

const corsOrigins = (nodeEnv: string): readonly string[] => {
  const value = process.env.CORS_ORIGINS;

  if (value === undefined) {
    if (nodeEnv === "production") {
      throw new Error("Missing required environment variable: CORS_ORIGINS");
    }

    return developmentCorsOrigins;
  }

  const origins = value
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

  if (origins.length === 0) {
    throw new Error("CORS_ORIGINS must contain at least one origin");
  }

  for (const origin of origins) {
    if (!URL.canParse(origin)) {
      throw new Error(`CORS_ORIGINS contains an invalid origin: ${origin}`);
    }

    const parsedOrigin = new URL(origin);
    const hasAllowedProtocol =
      nodeEnv === "production"
        ? parsedOrigin.protocol === "https:"
        : parsedOrigin.protocol === "http:" || parsedOrigin.protocol === "https:";

    if (!hasAllowedProtocol || parsedOrigin.origin !== origin) {
      throw new Error(`CORS_ORIGINS contains an invalid origin: ${origin}`);
    }
  }

  return origins;
};

const optionalPositiveInteger = (key: string): number | null => {
  const rawValue = process.env[key];
  if (!rawValue) return null;
  const value = Number(rawValue);
  return Number.isInteger(value) && value > 0 ? value : null;
};

const commaSeparated = (key: string): readonly string[] => {
  const rawValue = process.env[key];
  if (!rawValue) return [];
  return rawValue.split(",").map((value) => value.trim()).filter((value) => value.length > 0);
};

const nodeEnv = process.env.NODE_ENV ?? "development";

export const env = {
  nodeEnv,
  port: Number(process.env.PORT ?? 4000),
  corsOrigins: corsOrigins(nodeEnv),
  supabaseUrl: required("SUPABASE_URL"),
  supabaseAnonKey: required("SUPABASE_ANON_KEY"),
  supabaseServiceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
  jwtSecret: process.env.JWT_SECRET ?? "local-dev-secret",
  appleIapBundleId: process.env.APPLE_IAP_BUNDLE_ID ?? "com.inseong.coordit",
  appleIapAppAppleId: optionalPositiveInteger("APPLE_IAP_APPLE_ID"),
  appleIapRootCertificatePaths: commaSeparated("APPLE_IAP_ROOT_CERTIFICATE_PATHS"),
  appleIapEnabled: process.env.APPLE_IAP_ENABLED === "true",
  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? null,
  openRouterApiKey: process.env.OPENROUTER_API_KEY ?? null,
  openRouterModel: process.env.OPENROUTER_MODEL ?? "google/gemini-2.5-flash",
  openRouterTimeoutMs: integer("OPENROUTER_TIMEOUT_MS", 20_000),
  crawlTimeoutMs: integer("CRAWL_TIMEOUT_MS", 30_000),
  pageLoadTimeoutMs: integer("PAGE_LOAD_TIMEOUT_MS", 20_000),
  maxConcurrentPages: integer("MAX_CONCURRENT_PAGES", 2),
  maxRedirects: integer("MAX_REDIRECTS", 5),
  maxJsonResponseBytes: integer("MAX_JSON_RESPONSE_BYTES", 2_000_000),
  maxHtmlBytes: integer("MAX_HTML_BYTES", 5_000_000),
  maxImages: integer("MAX_IMAGES", 30),
  domainRequestDelayMs: integer("DOMAIN_REQUEST_DELAY_MS", 1_500),
  userRateLimitPerMinute: integer("USER_RATE_LIMIT_PER_MINUTE", 5),
  crawlerUserAgent: process.env.USER_AGENT ?? "CoorditProductImporter/1.0",
  admobRewardedAdUnitId: process.env.ADMOB_REWARDED_AD_UNIT_ID ?? "",
  admobRewardItem: process.env.ADMOB_REWARDED_REWARD_ITEM ?? "실타래",
  admobRewardAmount: integer("ADMOB_REWARDED_REWARD_AMOUNT", 1),
};
