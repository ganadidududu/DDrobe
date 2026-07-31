import type { SizeScore } from "../lib/types";
import { formatFitScore } from "../lib/fit-score";

export function SizeScoreTable({ scores }: { scores: SizeScore[] }) {
  return (
    <div className="overflow-hidden rounded-md border border-line">
      <table className="w-full text-left text-sm">
        <thead className="border-b border-line bg-neutral-50">
          <tr>
            <th className="p-3 font-medium">Size</th>
            <th className="p-3 font-medium">Score</th>
            <th className="p-3 font-medium">Label</th>
            <th className="p-3 font-medium">Distance</th>
            <th className="p-3 font-medium">Confidence</th>
          </tr>
        </thead>
        <tbody>
          {scores.map((score) => (
            <tr key={score.externalProductSizeId} className="border-b border-line last:border-b-0">
              <td className="p-3">{score.sizeLabel}</td>
              <td className="p-3">{formatFitScore(score.fitScore)}</td>
              <td className="p-3">{score.fitLabel}</td>
              <td className="p-3">{score.weightedFitDistance}</td>
              <td className="p-3">{score.recommendationConfidence ?? "-"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
