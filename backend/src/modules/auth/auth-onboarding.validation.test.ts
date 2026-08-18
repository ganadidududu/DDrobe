import assert from "node:assert/strict";
import {
  assertRejectsWithStatus,
  consentVersion,
  createFakeRepository,
  fixedNow,
  loadCompleteOnboarding,
  payload,
  type CompleteOnboardingWithRepository
} from "./auth-onboarding.test-fixtures";

const tests: readonly {
  readonly name: string;
  readonly run: (complete: CompleteOnboardingWithRepository) => Promise<void>;
}[] = [
  {
    name: "blank displayName returns 400 and writes nothing",
    run: async (complete) => {
      const fake = createFakeRepository();
      await assertRejectsWithStatus(
        () => complete(fake.repository, { id: "user-1", email: "user@example.com" }, payload({ displayName: "   " })),
        400
      );
      assert.deepEqual(fake.operations, []);
    }
  },
  {
    name: "missing required consent returns 400 and writes nothing",
    run: async (complete) => {
      const fake = createFakeRepository();
      await assertRejectsWithStatus(
        () =>
          complete(
            fake.repository,
            { id: "user-1", email: "user@example.com" },
            payload({ consents: { terms_of_service: { accepted: true, version: "2026-07-07" } } })
          ),
        400
      );
      assert.deepEqual(fake.operations, []);
    }
  },
  {
    name: "false required consent returns 400 and writes nothing",
    run: async (complete) => {
      const fake = createFakeRepository();
      await assertRejectsWithStatus(
        () =>
          complete(
            fake.repository,
            { id: "user-1", email: "user@example.com" },
            payload({
              consents: {
                terms_of_service: { accepted: false, version: "2026-07-07" },
                privacy_policy: { accepted: true, version: "2026-07-07" }
              }
            })
          ),
        400
      );
      assert.deepEqual(fake.operations, []);
    }
  },
  {
    name: "body measurements without numeric values create no row",
    run: async (complete) => {
      const fake = createFakeRepository();
      const result = await complete(
        fake.repository,
        { id: "user-1", email: "user@example.com" },
        payload({ bodyMeasurements: { heightCm: "", weightKg: null, note: "not numeric" } }),
        { now: fixedNow }
      );
      assert.equal(result.bodyMeasurementsSaved, false);
      assert.equal(fake.operations.some((operation) => operation.kind === "body"), false);
    }
  },
  {
    name: "non binary gender is rejected and writes nothing",
    run: async (complete) => {
      const fake = createFakeRepository();
      await assertRejectsWithStatus(
        () => complete(fake.repository, { id: "user-1", email: "user@example.com" }, payload({ gender: "non_binary" })),
        400
      );
      assert.deepEqual(fake.operations, []);
    }
  },
  {
    name: "unknown consent key returns 400 and writes nothing",
    run: async (complete) => {
      const fake = createFakeRepository();
      await assertRejectsWithStatus(
        () =>
          complete(
            fake.repository,
            { id: "user-1", email: "user@example.com" },
            payload({
              consents: {
                terms_of_service: { accepted: true, version: "2026-07-07" },
                privacy_policy: { accepted: true, version: "2026-07-07" },
                analytics_sale: { accepted: true, version: "2026-07-07" }
              }
            })
          ),
        400
      );
      assert.deepEqual(fake.operations, []);
    }
  },
  {
    name: "missing latest required consent version returns 500 and writes nothing",
    run: async (complete) => {
      const fake = createFakeRepository({ consentVersions: [consentVersion("terms_of_service", true)] });
      await assertRejectsWithStatus(
        () => complete(fake.repository, { id: "user-1", email: "user@example.com" }, payload()),
        500
      );
      assert.deepEqual(fake.operations, []);
    }
  },
  {
    name: "auth user missing email returns 400 and writes nothing",
    run: async (complete) => {
      const fake = createFakeRepository();
      await assertRejectsWithStatus(
        () => complete(fake.repository, { id: "user-1" }, payload()),
        400
      );
      assert.deepEqual(fake.operations, []);
    }
  }
];

const runTests = async (): Promise<void> => {
  const complete = await loadCompleteOnboarding();
  for (const test of tests) {
    await test.run(complete);
    console.log(`PASS ${test.name}`);
  }
};

runTests().catch((error: unknown) => {
  if (error instanceof Error) {
    console.error(error);
    process.exit(1);
  }
  console.error("Unknown test failure");
  process.exit(1);
});
