# Hybrid Scoring Readiness Data Contract

This artifact defines a bounded, privacy-preserving export shape for future fit recommendation analysis. It is a data contract only.

T8 does not ship ML training, model evaluation, prediction serving, shadow recommendations, report-model calculation of recommendations, or any change to the production recommendation path. The live engine remains the rule-based fit score engine, and OpenRouter remains a report-writing layer that consumes computed summaries only.

## Scope

The export is intended for offline analysis after enough feedback exists to compare:

- what Coordit recommended
- what size the user selected or purchased
- what fit outcome the user reported
- which body/garment parts caused issues
- which score explanation and confidence reasons the rule engine recorded
- what measurement source and parsing quality were used
- which algorithm version generated the recommendation

No database migration is required. Current fields already live in `fit_analysis_results`, `user_feedback`, `recommendation_logs`, `external_products`, `external_product_sizes`, and `fit_analysis_results.result_details`.

## Export Record

Schema version: `fit_learning_export_v1`

| JSONL path | Source table/path | Purpose | Privacy note |
| --- | --- | --- | --- |
| `schemaVersion` | Export helper constant | Version for this export contract. | No user data. |
| `exportRef` | Derived from `fit_analysis_results.id` by the export job, or fixture-provided pseudonymous reference | Allows offline row tracking without raw DB IDs. | Must be a pseudonym or run-local opaque reference, not the raw UUID. |
| `observedAt` | `fit_analysis_results.created_at` | Recommendation timestamp for trend analysis. | Timestamp can be retained; bucket by date for broader sharing. |
| `productContext.category` | `external_products.category` | Category-level analysis and minimum sample grouping. | Category only; no product URL or raw product payload. |
| `productContext.fitType` | `external_products.fit_type` | Separates slim/regular/relaxed/oversized recommendation behavior. | Fit type only. |
| `recommendation.recommendedSizeLabel` | `fit_analysis_results.recommended_size_label` | Recommended size to compare against purchased/chosen size. | Size label only. |
| `recommendation.fitScore` | `fit_analysis_results.fit_score` | Rule-based numeric score at recommendation time. | Derived score only. |
| `recommendation.fitLabel` | `fit_analysis_results.fit_label` | Rule-based fit band at recommendation time. | Derived label only. |
| `recommendation.weightedFitDistance` | `fit_analysis_results.weighted_fit_distance` | Distance signal used to inspect score calibration. | Derived metric only. |
| `recommendation.recommendationConfidence` | `fit_analysis_results.recommendation_confidence` | Public confidence label emitted by the engine. | Derived label only. |
| `recommendation.algorithmVersion` | `fit_analysis_results.algorithm_version` and `recommendation_logs.algorithm_version` | Separates analysis by scoring implementation. | Version string only. |
| `outcome.purchasedSizeLabel` | `user_feedback.purchased_size_label` | User-selected or purchased size when available. | Size label only; do not export order IDs or checkout data. |
| `outcome.actualFitRating` | `user_feedback.actual_fit_rating` | Numeric post-purchase fit feedback. | Derived user feedback only; no raw comment. |
| `outcome.actualFitLabel` | `user_feedback.actual_fit_label` | Post-purchase fit outcome label. | Label only; no raw comment. |
| `outcome.partFeedback` | Sanitized `user_feedback.part_feedback` | Part-level failure/success labels by measurement key. | Whitelist measurement keys and known labels; omit unknown keys and free text. |
| `engagement.eventType` | `recommendation_logs.event_type` | Separates shown/clicked/purchased events. | Event class only. |
| `engagement.clicked` | `recommendation_logs.clicked_at` presence | Click corroboration for feedback reliability. | Boolean only; no raw event payload. |
| `engagement.purchased` | `recommendation_logs.purchased_at` presence | Purchase corroboration for feedback reliability. | Boolean only; no raw event payload. |
| `scoreExplanation.comparedMeasurementCount` | `fit_analysis_results.result_details.scoreExplanation.comparedMeasurementCount` | Confirms how much measurable evidence was compared. | Derived count only. |
| `scoreExplanation.comparedMeasurements` | `result_details.scoreExplanation.comparedMeasurements` | Shows which measurements influenced the score. | Measurement keys only. |
| `scoreExplanation.missingMeasurementKeys` | `result_details.scoreExplanation.missingMeasurementKeys` | Explains sparse comparisons. | Measurement keys only. |
| `scoreExplanation.scoreGapToNextCandidate` | `result_details.scoreExplanation.scoreGapToNextCandidate` | Helps identify ambiguous recommendations. | Derived metric only. |
| `scoreExplanation.normalizedDistance` | `result_details.scoreExplanation.normalizedDistance` | Score calibration feature for future analysis. | Derived metric only. |
| `scoreExplanation.penalty` | `result_details.scoreExplanation.penalty` | Captures fit-type penalty context. | Derived metric only. |
| `scoreExplanation.referenceSampleCounts` | `result_details.scoreExplanation.referenceSampleCounts` | Shows reference garment support per measurement. | Counts only. |
| `scoreExplanation.topContributingParts` | `result_details.scoreExplanation.topContributingParts` | Part-level explanation of score contributors. | Derived part metrics only. |
| `scoreExplanation.reasonCodes` | `result_details.scoreExplanation.reasonCodes` | Rule-based explanation/caveat labels. | Known reason codes only. |
| `confidenceBreakdown.label` | `result_details.confidenceBreakdown.label` | Internal copy of public confidence label. | Derived label only. |
| `confidenceBreakdown.score` | `result_details.confidenceBreakdown.score` | Numeric confidence calibration signal. | Derived metric only. |
| `confidenceBreakdown.comparedMeasurementCount` | `result_details.confidenceBreakdown.comparedMeasurementCount` | Confidence evidence count. | Derived count only. |
| `confidenceBreakdown.scoreGapToNextCandidate` | `result_details.confidenceBreakdown.scoreGapToNextCandidate` | Confidence ambiguity signal. | Derived metric only. |
| `confidenceBreakdown.normalizedDistance` | `result_details.confidenceBreakdown.normalizedDistance` | Confidence distance signal. | Derived metric only. |
| `confidenceBreakdown.penalty` | `result_details.confidenceBreakdown.penalty` | Fit-type penalty signal. | Derived metric only. |
| `confidenceBreakdown.reasonCodes` | `result_details.confidenceBreakdown.reasonCodes` | Confidence caveat labels. | Known reason codes only. |
| `confidenceBreakdown.referenceSampleCounts` | `result_details.confidenceBreakdown.referenceSampleCounts` | Confidence support per measurement. | Counts only. |
| `confidenceBreakdown.feedbackReliability` | `result_details.confidenceBreakdown.feedbackReliability` | Captures whether feedback personalization was applied or gated. | Counts/status only; no raw feedback text. |
| `confidenceBreakdown.dataQuality` | `result_details.confidenceBreakdown.dataQuality` | Captures sparse or unverified measurement caveats. | Derived quality summary only; no raw OCR text. |
| `measurementSource.recommendedSizeLabel` | `external_product_sizes.size_label` for `fit_analysis_results.recommended_external_product_size_id` | Links measurement quality to the recommended size label. | Size label only. |
| `measurementSource.measurementSource` | `external_product_sizes.measurement_source` | Distinguishes manual, OCR, URL, or mocked measurements. | Source class only. |
| `measurementSource.parsingStatus` | `external_product_sizes.parsing_status` | Distinguishes confirmed/accepted/pending/failed parser states. | Status only. |
| `measurementSource.extractionConfidence` | `external_product_sizes.extraction_confidence` | Parser confidence for data-quality analysis. | Numeric confidence only. |

## Explicit Exclusions

The export must not include:

- `users.id`, `fit_analysis_results.id`, `reference_clothing_id`, `external_product_id`, `external_product_sizes.id`, or `user_feedback.id` as raw identifiers
- auth tokens, session data, emails, phone numbers, addresses, order IDs, or checkout payloads
- `user_feedback.comment`
- `user_feedback.raw_data`
- `recommendation_logs.raw_data`
- `external_products.product_url`
- `external_products.raw_product_data`
- `external_product_sizes.raw_size_data`
- `external_product_sizes.extracted_text`
- raw OCR payloads, raw parser payloads, raw product rows, or prompt-like free text

If offline analysis needs stable joins, generate `exportRef` with an environment-specific keyed hash or a run-local lookup table outside the JSONL file. Do not publish the salt/key with the export.

## Minimum Sample Caveats

This contract is not a readiness claim for model training.

- Category-level feedback personalization currently requires at least 5 usable category rows before full offsets apply.
- Part-level sensitivity currently requires at least 3 usable rows per measurement before a part multiplier applies.
- Any future ML or statistical analysis must set a higher analysis threshold per category, fit type, source quality bucket, and outcome label before drawing conclusions.
- Rows with missing outcomes, sparse measurements, unverified parser status, low extraction confidence, or conflicting feedback should remain analyzable but must not be treated as reliable labels without filtering.
- Small samples can support QA and schema validation only; they are not sufficient for model training, model selection, or production calibration.

## Read-Only Fixture Helper

`backend/src/modules/fit/fit-learning-export.ts` provides a fixture/injectable JSONL helper for contract verification only. It has no database access, network access, external ML dependency, model training path, prediction serving path, or shadow recommendation path.

The helper whitelists computed fields and omits raw/private fields even when malformed fixture rows contain comments, raw payloads, raw OCR text, private IDs, or auth tokens.

Top-level string fields are bounded before export: categories, fit types, fit labels, confidence labels, feedback labels, engagement event types, algorithm versions, measurement statuses, and size labels are retained only when they match known labels or safe short size-label syntax. Unknown, prompt-like, or private-looking strings are exported as `null` rather than carried through.
