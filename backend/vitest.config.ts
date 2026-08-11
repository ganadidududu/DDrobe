import { defineConfig } from "vitest/config";

process.env.SUPABASE_URL ??= "http://localhost:54321";
process.env.SUPABASE_ANON_KEY ??= "test-anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

export default defineConfig({
  test: {
    environment: "node",
    include: [
      "src/modules/product-import/tests/**/*.test.ts",
      "src/modules/clothing-items/clothing-items.service.test.ts",
      "src/modules/fit/fit.controller.test.ts",
      "src/modules/fit-report/fit-report.controller.test.ts",
      "src/modules/auth/auth-apple.http.test.ts",
      "src/config/env.test.ts",
      "src/middleware/**/*.test.ts"
    ]
  }
});
