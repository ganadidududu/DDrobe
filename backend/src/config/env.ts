import dotenv from "dotenv";

dotenv.config();

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

export const env = {
  nodeEnv: process.env.NODE_ENV ?? "development",
  port: Number(process.env.PORT ?? 4000),
  supabaseUrl: required("SUPABASE_URL"),
  supabaseAnonKey: required("SUPABASE_ANON_KEY"),
  supabaseServiceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
  jwtSecret: process.env.JWT_SECRET ?? "local-dev-secret",
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
};
