import assert from "node:assert/strict";
import {
  bodyRow,
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
    name: "minimal success saves required consents only and no body row",
    run: async (complete) => {
      const fake = createFakeRepository();
      const result = await complete(fake.repository, { id: "user-1", email: "user@example.com" }, payload(), {
        now: fixedNow
      });
      assert.equal(result.user.display_name, "Mina");
      assert.equal(result.bodyMeasurementsSaved, false);
      assert.deepEqual(
        result.consentRows.map((consent) => consent.consent_key),
        ["terms_of_service", "privacy_policy"]
      );
      assert.deepEqual(fake.operations.map((operation) => operation.kind), ["user", "consent", "consent"]);
    }
  },
  {
    name: "full birth date persists with only height and weight from onboarding",
    run: async (complete) => {
      const fake = createFakeRepository();
      const result = await complete(
        fake.repository,
        { id: "user-1", email: "user@example.com" },
        payload({
          gender: "female",
          birthDate: "1994-05-17",
          bodyMeasurements: { heightCm: 168, weightKg: 54 },
          consents: {
            terms_of_service: { accepted: true, version: "2026-07-07" },
            privacy_policy: { accepted: true, version: "2026-07-07" },
            fit_data_improvement: { accepted: true, version: "2026-07-07" },
            marketing: { accepted: false, version: "2026-07-07" }
          }
        }),
        { now: fixedNow }
      );
      assert.equal(result.bodyMeasurementsSaved, true);
      assert.deepEqual(
        result.consentRows.map((consent) => consent.consent_key),
        ["terms_of_service", "privacy_policy", "fit_data_improvement", "marketing"]
      );
      assert.equal(fake.users[0]?.gender, "female");
      assert.equal(fake.users[0]?.birth_date, "1994-05-17");
      assert.equal(fake.users[0]?.birth_year, 1994);
      assert.equal(fake.operations.filter((operation) => operation.kind === "body").length, 1);
      assert.deepEqual(fake.writtenBodies[0], {
        height_cm: 168,
        weight_kg: 54,
        raw_data: { source: "onboarding" }
      });
      assert.equal(fake.writtenBodies[0]?.raw_data.source, "onboarding");
    }
  },
  {
    name: "retry body measurements updates existing onboarding row",
    run: async (complete) => {
      const fake = createFakeRepository({ existingBodyMeasurements: [bodyRow("existing-body")] });
      await complete(
        fake.repository,
        { id: "user-1", email: "user@example.com" },
        payload({ bodyMeasurements: { heightCm: 171 } }),
        { now: fixedNow }
      );
      assert.equal(fake.bodyRows.length, 1);
      assert.deepEqual(fake.operations.filter((operation) => operation.kind === "body"), [
        { kind: "body", action: "update", id: "existing-body" }
      ]);
    }
  },
  {
    name: "omitted optional consents are absent",
    run: async (complete) => {
      const fake = createFakeRepository();
      await complete(fake.repository, { id: "user-1", email: "user@example.com" }, payload(), { now: fixedNow });
      assert.deepEqual(
        fake.consents.map((consent) => consent.consent_key),
        ["terms_of_service", "privacy_policy"]
      );
    }
  },
  {
    name: "optional false consent is allowed",
    run: async (complete) => {
      const fake = createFakeRepository();
      await complete(
        fake.repository,
        { id: "user-1", email: "user@example.com" },
        payload({
          consents: {
            terms_of_service: { accepted: true, version: "2026-07-07" },
            privacy_policy: { accepted: true, version: "2026-07-07" },
            marketing: { accepted: false, version: "2026-07-07" }
          }
        }),
        { now: fixedNow }
      );
      assert.equal(fake.consents.find((consent) => consent.consent_key === "marketing")?.accepted, false);
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
