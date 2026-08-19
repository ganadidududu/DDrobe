import assert from "node:assert/strict";

process.env.SUPABASE_URL = process.env.SUPABASE_URL ?? "http://localhost:54321";
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? "anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "service-role-key";

const run = async (): Promise<void> => {
  const { toUserProfileUpsertRow } = await import("./users.service");
  const row = toUserProfileUpsertRow({
    id: "returning-user",
    email: "returning@example.com"
  });

  assert.equal(
    Object.hasOwn(row, "display_name"),
    false,
    "An identity-only Google login must not erase a completed user's display name."
  );
};

void run().then(
  () => console.log("users.service tests passed"),
  (error: unknown) => {
    console.error(error);
    process.exitCode = 1;
  }
);
