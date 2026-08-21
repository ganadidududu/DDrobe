import assert from "node:assert/strict";
import { z } from "zod";
import { createCachedVerifierKeyProvider } from "./admob-reward.keys";
import {
  createCanonicalSignedContent,
  loadControllerFactory,
  startTestHarness,
  testConfiguration,
  testNowMs,
  type CallbackValues
} from "./admob-reward.test-harness";

const scenarioSchema = z.enum(["valid", "invalid-signature", "validation-probe"]);
const settlementSchema = z.object({
  status: z.literal("granted"),
  availableThreads: z.literal(37)
}).strict();
const validationSchema = z.object({ status: z.literal("validation") }).strict();

const attemptId = "845628bf-1362-4f64-937d-e947aa1d017f";

const baseValues = (customData: string | null = attemptId): CallbackValues => ({
  adNetwork: "1953547073528090325",
  adUnit: testConfiguration.adUnitId,
  customData,
  rewardAmount: String(testConfiguration.rewardAmount),
  rewardItem: testConfiguration.rewardItem,
  timestamp: String(testNowMs),
  transactionId: "18fa792de1bca816048293fc71035638",
  userId: "test-user"
});

const selectedScenario = (): z.infer<typeof scenarioSchema> => {
  const flagIndex = process.argv.indexOf("--scenario");
  return scenarioSchema.parse(flagIndex >= 0 ? process.argv[flagIndex + 1] : undefined);
};

const runPrimaryScenario = async (
  scenario: z.infer<typeof scenarioSchema>
): Promise<{ readonly status: number; readonly grantCalls: number }> => {
  const factory = await loadControllerFactory();
  const isValidationProbe = scenario === "validation-probe";
  const harness = await startTestHarness(
    factory,
    !isValidationProbe,
    isValidationProbe
      ? {
        adUnitId: "",
        rewardItem: "unconfigured",
        rewardAmount: 999
      }
      : {}
  );
  try {
    const customData = scenario === "validation-probe"
      ? testConfiguration.validationCustomData
      : attemptId;
    const content = createCanonicalSignedContent(baseValues(customData));

    // When: the selected signed callback is sent through a real Express listener.
    const response = await harness.requestSigned({
      requestContent: content,
      mutateSignature: scenario === "invalid-signature"
    });

    // Then: the public response and grant-call count match the selected contract.
    switch (scenario) {
      case "valid":
        assert.equal(response.status, 200);
        settlementSchema.parse(await response.json());
        assert.deepEqual(harness.grantCalls(), [{
          attemptId,
          transactionId: baseValues().transactionId
        }]);
        break;
      case "invalid-signature":
        assert.equal(response.status, 400);
        assert.equal(harness.grantCalls().length, 0);
        break;
      case "validation-probe":
        assert.equal(response.status, 200);
        assert.deepEqual(validationSchema.parse(await response.json()), {
          status: "validation"
        });
        assert.equal(harness.grantCalls().length, 0);
        break;
      default:
        assert.fail("Unexpected AdMob SSV test scenario");
    }
    return { status: response.status, grantCalls: harness.grantCalls().length };
  } finally {
    await harness.close();
  }
};

const assertRejected = async (input: {
  readonly requestContent: string;
  readonly contentToSign?: string;
  readonly keyId?: number;
  readonly tailOrder?: "google" | "reversed";
  readonly enabled?: boolean;
}): Promise<string> => {
  const factory = await loadControllerFactory();
  const harness = await startTestHarness(factory, input.enabled ?? true);
  try {
    // When: a signature-valid but contract-invalid callback reaches Express.
    const response = await harness.requestSigned(input);

    // Then: it is rejected without entering the grant dependency.
    assert.ok(response.status >= 400);
    assert.equal(harness.grantCalls().length, 0);
    assert.equal(harness.rejectionCategories().length, 1);
    const category = harness.rejectionCategories()[0];
    assert.ok(category);
    return category;
  } finally {
    await harness.close();
  }
};

const assertRawRejected = async (rawQuery: string): Promise<string> => {
  const factory = await loadControllerFactory();
  const harness = await startTestHarness(factory);
  try {
    // When: an unsigned callback-shaped query reaches the real Express route.
    const response = await harness.requestRawQuery(rawQuery);

    // Then: it is rejected and cannot reach the grant dependency.
    assert.ok(response.status >= 400);
    assert.equal(harness.grantCalls().length, 0);
    assert.equal(harness.rejectionCategories().length, 1);
    const category = harness.rejectionCategories()[0];
    assert.ok(category);
    return category;
  } finally {
    await harness.close();
  }
};

const verifyKeyCacheBoundary = async (): Promise<void> => {
  // Given: a deterministic clock and a downloader that records each refresh.
  let currentTime = testNowMs;
  let downloadCalls = 0;
  const provider = createCachedVerifierKeyProvider(
    async () => {
      downloadCalls += 1;
      return { keys: [{ keyId: 7, pem: "public-key-fixture" }] };
    },
    () => currentTime
  );

  // When: keys are requested before and exactly at the 24-hour boundary.
  await provider();
  currentTime = testNowMs + 86_399_999;
  await provider();
  assert.equal(downloadCalls, 1);
  currentTime = testNowMs + 86_400_000;
  await provider();

  // Then: the cache never survives for longer than 24 hours.
  assert.equal(downloadCalls, 2);
};

const runFailureMatrix = async (): Promise<number> => {
  const canonical = createCanonicalSignedContent(baseValues());
  const segments = canonical.split("&");
  const first = segments[0];
  const second = segments[1];
  assert.ok(first && second);
  const reordered = [second, first, ...segments.slice(2)].join("&");
  const malformedEncoding = canonical.replace(
    `reward_item=${encodeURIComponent(testConfiguration.rewardItem)}`,
    "reward_item=%ZZ"
  );
  const categories = [
    await assertRejected({ requestContent: reordered }),
    await assertRejected({
      requestContent: canonical,
      contentToSign: decodeURIComponent(canonical)
    }),
    await assertRejected({ requestContent: malformedEncoding }),
    await assertRejected({
      requestContent: createCanonicalSignedContent({
        ...baseValues(),
        timestamp: String(testNowMs - 86_400_001)
      })
    }),
    await assertRejected({
      requestContent: createCanonicalSignedContent({
        ...baseValues(),
        adUnit: "ca-app-pub-0000000000000000/0000000000"
      })
    }),
    await assertRejected({
      requestContent: createCanonicalSignedContent({
        ...baseValues(),
        rewardAmount: "2"
      })
    }),
    await assertRejected({
      requestContent: createCanonicalSignedContent({
        ...baseValues(),
        rewardItem: "coin"
      })
    }),
    await assertRejected({ requestContent: canonical, keyId: 999_999_999 }),
    await assertRejected({
      requestContent: createCanonicalSignedContent(baseValues("arbitrary-data"))
    }),
    await assertRejected({
      requestContent: createCanonicalSignedContent(baseValues(null))
    }),
    await assertRejected({ requestContent: canonical, tailOrder: "reversed" }),
    await assertRejected({ requestContent: canonical, enabled: false }),
    await assertRawRejected(canonical),
    await assertRawRejected(""),
    await assertRawRejected(
      `custom_data=${encodeURIComponent(testConfiguration.validationCustomData)}`
    ),
    await assertRejected({
      requestContent: createCanonicalSignedContent(
        baseValues(testConfiguration.validationCustomData)
      ),
      contentToSign: canonical
    }),
    await assertRejected({
      requestContent: createCanonicalSignedContent({
        ...baseValues(testConfiguration.validationCustomData),
        timestamp: String(testNowMs - 86_400_001)
      })
    })
  ];

  // Category-only diagnostics must not contain provider callback payload fragments.
  const diagnosticFixture = JSON.stringify(categories);
  assert.doesNotMatch(diagnosticFixture, /signature=|custom_data=|transaction_id=|BEGIN .*PRIVATE/u);
  assert.ok(categories.includes("invalid-signature"));
  assert.ok(categories.includes("unexpected-reward-config"));
  assert.ok(categories.includes("missing-custom-data"));
  assert.ok(categories.includes("malformed-callback"));
  await verifyKeyCacheBoundary();
  return categories.length;
};

const main = async (): Promise<void> => { // no-excuse-ok: catch
  const scenario = selectedScenario();
  const result = await runPrimaryScenario(scenario);
  const rejectedEdgeCases = await runFailureMatrix();
  console.log(
    `SUMMARY scenario=${scenario} status=${result.status} grantCalls=${result.grantCalls}`
  );
  console.log(
    `EDGE_SUMMARY rejected=${rejectedEdgeCases} grantCalls=0 cacheRefreshesAt24h=1`
  );
};

main().catch((error: unknown) => { // no-excuse-ok: catch
  if (error instanceof Error) {
    console.error(error.message);
  } else {
    console.error("Unknown AdMob SSV test failure");
  }
  process.exit(1);
});
