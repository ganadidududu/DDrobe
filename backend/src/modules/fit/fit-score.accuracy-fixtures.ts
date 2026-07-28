import assert from "node:assert/strict";
import { recommendBestSizeWithReferences } from "./fit-score.engine";
import { fitAccuracyFixtures } from "./fit-score.accuracy-fixtures.data";
import { fitAccuracyAdditionalFixtures } from "./fit-score.accuracy-fixtures.more";
import type { AccuracyFixture } from "./fit-score.accuracy-fixtures.data";
import type { BestSizeRecommendation, MeasurementKey } from "./fit.types";

type ScoreBand = {
  readonly min: number;
  readonly max: number;
};

const assertScoreBand = (scenarioName: string, score: number, band: ScoreBand): void => {
  assert.ok(
    score >= band.min && score <= band.max,
    `${scenarioName}: expected score ${score} to be between ${band.min} and ${band.max}`
  );
};

const assertComparedMeasurements = (
  scenarioName: string,
  actual: readonly MeasurementKey[],
  expected: readonly MeasurementKey[]
): void => {
  assert.deepEqual(
    [...actual].sort(),
    [...expected].sort(),
    `${scenarioName}: compared measurements changed`
  );
};

const measurementKeys: readonly MeasurementKey[] = [
  "shoulder_width",
  "chest_width",
  "total_length",
  "sleeve_length",
  "waist_width",
  "hip_width",
  "rise",
  "outseam"
];

const assertReferenceSamples = (
  scenarioName: string,
  recommendation: BestSizeRecommendation,
  expectedSamples: Partial<Record<MeasurementKey, number>>
): void => {
  for (const key of measurementKeys) {
    const sampleCount = expectedSamples[key];
    if (typeof sampleCount !== "number") continue;

    assert.equal(
      recommendation.referenceProfile?.sampleCounts[key],
      sampleCount,
      `${scenarioName}: expected ${key} sample count`
    );
  }
};

const assertObservableRecommendation = (
  fixture: AccuracyFixture,
  recommendation: BestSizeRecommendation
): void => {
  const recommended = recommendation.recommended;

  assert.equal(recommended.sizeLabel, fixture.expectedSizeLabel, `${fixture.name}: recommended size`);
  assertScoreBand(fixture.name, recommended.finalFitScore, fixture.expectedScoreBand);
  assertComparedMeasurements(
    fixture.name,
    recommended.comparedMeasurements,
    fixture.expectedComparedMeasurements
  );
  assert.equal(
    recommended.recommendationConfidence,
    fixture.expectedConfidence,
    `${fixture.name}: confidence`
  );
  assert.equal(
    recommendation.weightingStrategy,
    fixture.expectedWeightingStrategy,
    `${fixture.name}: weighting strategy`
  );
  assert.equal(recommended.algorithmVersion, "mvp_rule_v1_6", `${fixture.name}: algorithm version`);
  assert.ok(recommended.fitComment.length > 0, `${fixture.name}: fit comment metadata`);
  assert.ok(recommended.partExplanations.length > 0, `${fixture.name}: part explanation metadata`);
  assert.ok(
    Object.keys(recommended.partStatuses).length >= fixture.expectedComparedMeasurements.length,
    `${fixture.name}: part status metadata`
  );
  assert.equal(
    recommended.scoreExplanation.comparedMeasurementCount,
    fixture.expectedComparedMeasurements.length,
    `${fixture.name}: explanation compared count`
  );
  assertComparedMeasurements(
    fixture.name,
    recommended.scoreExplanation.comparedMeasurements,
    fixture.expectedComparedMeasurements
  );
  assert.equal(
    recommended.confidenceBreakdown.label,
    recommended.recommendationConfidence,
    `${fixture.name}: confidence breakdown label`
  );
  assert.equal(
    recommended.confidenceBreakdown.normalizedDistance,
    recommended.weightedFitDistance,
    `${fixture.name}: confidence distance`
  );
  assert.equal(
    recommended.scoreExplanation.penalty,
    recommended.penalty,
    `${fixture.name}: explanation penalty`
  );
  assert.ok(
    recommended.scoreExplanation.topContributingParts.length > 0,
    `${fixture.name}: top contributing parts`
  );

  for (const reasonCode of fixture.expectedReasonCodes ?? []) {
    assert.ok(
      recommended.scoreExplanation.reasonCodes.includes(reasonCode),
      `${fixture.name}: score explanation reason ${reasonCode}`
    );
    assert.ok(
      recommended.confidenceBreakdown.reasonCodes.includes(reasonCode),
      `${fixture.name}: confidence breakdown reason ${reasonCode}`
    );
  }
  if (fixture.expectedReasonCodes && fixture.expectedReasonCodes.length > 0) {
    console.log(`reason codes asserted: ${fixture.name}: ${fixture.expectedReasonCodes.join(", ")}`);
  }

  if (fixture.expectedReferenceSamples) {
    assertReferenceSamples(fixture.name, recommendation, fixture.expectedReferenceSamples);
  }

  if (typeof fixture.expectedFeedbackSampleCount === "number") {
    assert.equal(
      recommendation.feedbackProfile?.sampleCount,
      fixture.expectedFeedbackSampleCount,
      `${fixture.name}: feedback metadata`
    );
  }
};

export const runFitAccuracyFixtureTests = (): void => {
  for (const fixture of [...fitAccuracyFixtures, ...fitAccuracyAdditionalFixtures]) {
    const recommendation = recommendBestSizeWithReferences(
      [...fixture.references],
      [...fixture.sizes],
      fixture.category,
      fixture.feedbackProfile
    );

    assertObservableRecommendation(fixture, recommendation);
    console.log(`fixture passed: ${fixture.name}`);
  }
};
