export const formatFitScore = (score: number): string =>
  Number.isFinite(score) ? score.toFixed(1) : "—";
