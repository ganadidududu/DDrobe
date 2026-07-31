import type { FitRecommendationResponse } from "../lib/types";
import { formatFitScore } from "../lib/fit-score";
import { Card } from "./Card";

export function FitScoreResultCard({ result }: { result: FitRecommendationResponse }) {
  return (
    <Card className="border-ink">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-muted">Recommended size</p>
        <span className="rounded-full bg-ink px-3 py-1 text-xs font-semibold text-white">
          {result.recommendationConfidence}
        </span>
      </div>
      <div className="mt-3 flex items-end justify-between gap-4">
        <h2 className="text-5xl font-semibold">{result.recommendedSize}</h2>
        <p className="text-2xl font-semibold">{formatFitScore(result.fitScore)}</p>
      </div>
      <div className="mt-4 h-2 rounded-full bg-neutral-100">
        <div className="h-2 rounded-full bg-ink" style={{ width: `${Math.min(100, Math.max(0, result.fitScore))}%` }} />
      </div>
      <p className="mt-4 text-sm font-medium">{result.fitLabel}</p>
      <p className="mt-3 text-sm leading-6 text-muted">{result.fitComment}</p>
      {result.partExplanations.length ? (
        <ul className="mt-4 grid gap-2 text-sm text-muted">
          {result.partExplanations.map((explanation) => (
            <li key={explanation}>{explanation}</li>
          ))}
        </ul>
      ) : null}
    </Card>
  );
}
