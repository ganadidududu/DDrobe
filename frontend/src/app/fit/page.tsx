"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { api } from "../../lib/api";
import { formatFitScore } from "../../lib/fit-score";
import { IMG } from "../../lib/images";
import { TopBar } from "../../components/TopBar";
import { Footer } from "../../components/Footer";
import type { FitData as Body3DFitData, Measurements as Body3DMeasurements } from "../../components/Body3D";
import { ConfidenceExplanationText } from "./confidence-display";
import type { ConfidenceDisplayResult } from "./confidence-display";

const Body3D = dynamic(() => import("../../components/Body3D"), { ssr: false });

// ─── Types ────────────────────────────────────────────────────────────

interface ClothingItem {
  id: string;
  name: string;
  brand?: string;
  category: string;
  size_label?: string;
  image_url?: string;
  raw_product_data?: Record<string, unknown>;
}

interface BodyMeasurement {
  id: string;
  height_cm?: number;
  weight_kg?: number;
  shoulder_width?: number;
  chest_circumference?: number;
  waist_circumference?: number;
  hip_circumference?: number;
  outseam?: number;
  created_at: string;
}

interface FitAnalysisResult extends ConfidenceDisplayResult {
  id: string;
  recommended_size_label: string;
  fit_score: number;
  fit_label: string;
  fit_comment: string;
  recommendation_confidence: "high" | "medium" | "low";
  result_details?: {
    partStatuses?: Record<string, "very_similar" | "slightly_small" | "slightly_large" | "large_gap">;
    diffs?: Record<string, number>;
    partExplanations?: string[];
    scoreExplanation?: ConfidenceDisplayResult["scoreExplanation"];
    confidenceBreakdown?: ConfidenceDisplayResult["confidenceBreakdown"];
  };
  created_at: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────

function scoreColor(score: number): string {
  if (score >= 85) return "var(--fit-perfect)";
  if (score >= 70) return "var(--camel)";
  if (score >= 50) return "#c49a3c";
  return "var(--fit-tight)";
}

function fitLabelToKorean(label: string): string {
  switch (label) {
    case "very_good_fit": return "Perfect";
    case "good_fit":      return "Good";
    case "acceptable":    return "OK";
    case "slightly_small":
    case "slightly_large": return "Caution";
    case "too_small":
    case "too_large":     return "Issue";
    default:              return label;
  }
}

function confidenceToPct(confidence: "high" | "medium" | "low" | undefined): number {
  switch (confidence) {
    case "high":   return 94;
    case "medium": return 75;
    case "low":    return 55;
    default:       return 0;
  }
}

const PART_NAMES: Record<string, string> = {
  shoulder_width: "어깨 너비",
  chest_width:    "가슴 단면",
  waist_width:    "허리 단면",
  hip_width:      "힙 단면",
  sleeve_length:  "소매 길이",
  total_length:   "총장",
  rise:           "밑위",
  outseam:         "아웃심",
};

function partStatusToScore(status: "very_similar" | "slightly_small" | "slightly_large" | "large_gap"): number {
  switch (status) {
    case "very_similar":    return 92;
    case "slightly_small":
    case "slightly_large":  return 72;
    case "large_gap":       return 45;
  }
}

function partStatusToColor(status: "very_similar" | "slightly_small" | "slightly_large" | "large_gap"): string {
  switch (status) {
    case "very_similar":   return "var(--fit-perfect)";
    case "slightly_small":
    case "slightly_large": return "var(--camel)";
    case "large_gap":      return "var(--fit-tight)";
  }
}

// ─── MeasField (module scope — must NOT be inside MySizePanel to avoid remount) ───

const measInputStyle: React.CSSProperties = {
  width: "100%",
  padding: "9px 12px",
  border: "1px solid var(--line)",
  borderRadius: 2,
  background: "transparent",
  outline: "none",
  fontFamily: "JetBrains Mono, monospace",
  fontSize: 13,
  color: "var(--obsidian)",
};

const measLabelStyle: React.CSSProperties = {
  display: "block",
  marginBottom: 4,
  fontSize: 10,
  fontFamily: "JetBrains Mono, monospace",
  letterSpacing: "0.12em",
  textTransform: "uppercase",
  color: "var(--text-muted)",
};

function MeasField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <label style={measLabelStyle}>{label}</label>
      <input
        type="number"
        step="0.1"
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder="—"
        style={measInputStyle}
      />
    </div>
  );
}

// ─── MySizePanel ──────────────────────────────────────────────────────

interface MySizePanelProps {
  onSaved: () => void;
}

type SaveStatus = "idle" | "saving" | "saved" | "error";

function MySizePanel({ onSaved }: MySizePanelProps) {
  const [topFields, setTopFields] = useState({
    total_length:   "",
    chest_width:    "",
    shoulder_width: "",
    sleeve_length:  "",
  });
  const [bottomFields, setBottomFields] = useState({
    bottom_total_length: "",
    waist_width:         "",
    hip_width:           "",
    thigh_width:         "",
    rise:                "",
    hem:                 "",
  });
  const [status, setStatus] = useState<SaveStatus>("idle");
  const [errorMsg, setErrorMsg] = useState("");

  const hasAnyValue =
    Object.values(topFields).some(v => Number.isFinite(parseFloat(v))) ||
    Object.values(bottomFields).some(v => Number.isFinite(parseFloat(v)));

  const handleSave = async () => {
    if (!hasAnyValue) return;
    setStatus("saving");
    setErrorMsg("");
    try {
      const body: Record<string, unknown> = {};
      // Schema columns
      if (Number.isFinite(parseFloat(topFields.shoulder_width)))
        body.shoulder_width = parseFloat(topFields.shoulder_width);
      if (Number.isFinite(parseFloat(topFields.chest_width)))
        body.chest_circumference = parseFloat(topFields.chest_width);
      if (Number.isFinite(parseFloat(bottomFields.waist_width)))
        body.waist_circumference = parseFloat(bottomFields.waist_width);
      if (Number.isFinite(parseFloat(bottomFields.hip_width)))
        body.hip_circumference = parseFloat(bottomFields.hip_width);
      // Extra fields → raw_data JSONB (rise ≠ outseam; total_length/sleeve_length/thigh/hem have no direct column)
      const rawData: Record<string, number> = {};
      const extras: Array<[string, string]> = [
        ["total_length",        topFields.total_length],
        ["sleeve_length",       topFields.sleeve_length],
        ["bottom_total_length", bottomFields.bottom_total_length],
        ["thigh_width",         bottomFields.thigh_width],
        ["rise",                bottomFields.rise],
        ["hem",                 bottomFields.hem],
      ];
      for (const [k, v] of extras) {
        if (Number.isFinite(parseFloat(v))) rawData[k] = parseFloat(v);
      }
      if (Object.keys(rawData).length > 0) body.raw_data = rawData;

      await api<BodyMeasurement>("/body-measurements", { method: "POST", body });
      setStatus("saved");
      onSaved();
      setTimeout(() => setStatus("idle"), 2500);
    } catch (e) {
      setStatus("error");
      setErrorMsg(e instanceof Error ? e.message : "저장에 실패했습니다.");
    }
  };

  return (
    <section style={{ padding: "32px 48px 0", maxWidth: 1600, margin: "0 auto" }}>
      <div style={{
        background: "var(--bg-raised)",
        border: "1px solid var(--line)",
        borderRadius: 4,
        padding: "28px 36px",
      }}>
        <div className="eyebrow" style={{ marginBottom: 8 }}>MY FIT PROFILE · MEASUREMENTS</div>
        <h3 className="korean-serif" style={{
          margin: "0 0 28px",
          fontSize: 24,
          fontWeight: 500,
          fontFamily: "var(--font-korean-display)",
        }}>
          내 신체 실측값
        </h3>

        {/* TOP section */}
        <div style={{ marginBottom: 24 }}>
          <div style={{ fontSize: 11, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.12em", color: "var(--camel)", marginBottom: 16, textTransform: "uppercase" }}>
            상의 · TOP
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12 }}>
            <MeasField label="총장 (cm)" value={topFields.total_length} onChange={v => setTopFields(f => ({ ...f, total_length: v }))} />
            <MeasField label="가슴단면 (cm)" value={topFields.chest_width} onChange={v => setTopFields(f => ({ ...f, chest_width: v }))} />
            <MeasField label="어깨너비 (cm)" value={topFields.shoulder_width} onChange={v => setTopFields(f => ({ ...f, shoulder_width: v }))} />
            <MeasField label="소매길이 (cm)" value={topFields.sleeve_length} onChange={v => setTopFields(f => ({ ...f, sleeve_length: v }))} />
          </div>
        </div>

        {/* BOTTOM section */}
        <div style={{ marginBottom: 28, paddingTop: 20, borderTop: "1px solid var(--line)" }}>
          <div style={{ fontSize: 11, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.12em", color: "var(--camel)", marginBottom: 16, textTransform: "uppercase" }}>
            하의 · BOTTOM
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 12 }}>
            <MeasField label="총장 (cm)" value={bottomFields.bottom_total_length} onChange={v => setBottomFields(f => ({ ...f, bottom_total_length: v }))} />
            <MeasField label="허리단면 (cm)" value={bottomFields.waist_width} onChange={v => setBottomFields(f => ({ ...f, waist_width: v }))} />
            <MeasField label="엉덩이단면 (cm)" value={bottomFields.hip_width} onChange={v => setBottomFields(f => ({ ...f, hip_width: v }))} />
            <MeasField label="허벅지단면 (cm)" value={bottomFields.thigh_width} onChange={v => setBottomFields(f => ({ ...f, thigh_width: v }))} />
            <MeasField label="밑위 (cm)" value={bottomFields.rise} onChange={v => setBottomFields(f => ({ ...f, rise: v }))} />
            <MeasField label="밑단단면 (cm)" value={bottomFields.hem} onChange={v => setBottomFields(f => ({ ...f, hem: v }))} />
          </div>
        </div>

        {status === "error" && (
          <div style={{ marginBottom: 16, padding: "8px 12px", background: "rgba(168,66,58,0.08)", border: "1px solid rgba(168,66,58,0.2)", borderRadius: 2, fontSize: 12, color: "var(--fit-tight)", fontFamily: "var(--font-korean)" }}>
            {errorMsg}
          </div>
        )}

        <div style={{ display: "flex", justifyContent: "flex-end" }}>
          <button
            className="btn btn-primary"
            onClick={handleSave}
            disabled={!hasAnyValue || status === "saving"}
            style={{ opacity: !hasAnyValue || status === "saving" ? 0.5 : 1 }}
          >
            {status === "saving" ? "저장중..." : status === "saved" ? "저장됨 ✓" : "측정값 저장"}
          </button>
        </div>
      </div>
    </section>
  );
}

// ─── Corner Registration Mark ─────────────────────────────────────────

function CornerMark({ top, left, right, bottom }: { top?: 0; left?: 0; right?: 0; bottom?: 0 }) {
  const style: React.CSSProperties = {
    position: "absolute",
    width: 16,
    height: 16,
    borderColor: "var(--camel)",
    borderStyle: "solid",
    borderWidth: 0,
    ...(top    === 0 ? { top: 12 }    : {}),
    ...(bottom === 0 ? { bottom: 12 } : {}),
    ...(left   === 0 ? { left: 12 }   : {}),
    ...(right  === 0 ? { right: 12 }  : {}),
    ...(top    === 0 && left  === 0 ? { borderTopWidth: 1, borderLeftWidth: 1 }    : {}),
    ...(top    === 0 && right === 0 ? { borderTopWidth: 1, borderRightWidth: 1 }   : {}),
    ...(bottom === 0 && left  === 0 ? { borderBottomWidth: 1, borderLeftWidth: 1 } : {}),
    ...(bottom === 0 && right === 0 ? { borderBottomWidth: 1, borderRightWidth: 1 }: {}),
  };
  return <div style={style} />;
}

// ─── Body3D data mapping ──────────────────────────────────────────────

function buildFitData(
  partStatuses: Record<string, "very_similar" | "slightly_small" | "slightly_large" | "large_gap"> | undefined,
  diffs: Record<string, number>,
): Body3DFitData | null {
  if (!partStatuses) return null;

  const toState = (key: string): "tight" | "perfect" | "loose" => {
    const s = partStatuses[key];
    if (!s || s === "very_similar") return "perfect";
    if (s === "slightly_small") return "tight";
    if (s === "slightly_large") return "loose";
    return (diffs[key] ?? 0) >= 0 ? "loose" : "tight";
  };
  const toLabel = (key: string): string => {
    const st = toState(key);
    return st === "perfect" ? "Perfect" : st === "tight" ? "Tight" : "Loose";
  };
  const toDelta = (key: string): string | undefined => {
    const d = diffs[key];
    if (!Number.isFinite(d)) return undefined;
    return `${d > 0 ? "+" : ""}${d.toFixed(1)}cm`;
  };

  return {
    shoulder: { state: toState("shoulder_width"), label: toLabel("shoulder_width"), delta: toDelta("shoulder_width") },
    chest:    { state: toState("chest_width"),    label: toLabel("chest_width"),    delta: toDelta("chest_width") },
    waist:    { state: toState("waist_width"),    label: toLabel("waist_width"),    delta: toDelta("waist_width") },
    hip:      { state: toState("hip_width"),      label: toLabel("hip_width"),      delta: toDelta("hip_width") },
  };
}

// ─── FitLab Page ──────────────────────────────────────────────────────

const SIZES = ["XS", "S", "M", "L", "XL"];

const RELATED_ITEMS = [
  { img: IMG.coat,    name: "헤리티지 카멜 코트",        fitLabel: "Perfect", score: 95, size: "M" },
  { img: IMG.knit,    name: "클라우드 캐시미어 니트",     fitLabel: "Loose",   score: 88, size: "S" },
  { img: IMG.trouser, name: "프리시전 플리츠 트라우저",   fitLabel: "Perfect", score: 96, size: "M" },
  { img: IMG.shirt,   name: "아키텍처럴 포플린 셔츠",     fitLabel: "Tight",   score: 82, size: "L" },
];

const DETAIL_ROWS: Array<{
  part: string;
  bodyKey: keyof BodyMeasurement | null;
  diffKey: string | null;
}> = [
  { part: "어깨 너비",  bodyKey: "shoulder_width",      diffKey: "shoulder_width" },
  { part: "가슴 단면",  bodyKey: "chest_circumference",  diffKey: "chest_width" },
  { part: "허리 단면",  bodyKey: "waist_circumference",  diffKey: "waist_width" },
  { part: "힙 단면",   bodyKey: "hip_circumference",    diffKey: "hip_width" },
  { part: "아웃심",      bodyKey: "outseam",               diffKey: "outseam" },
];

export default function FitLabPage() {
  const router = useRouter();

  const [closetItems, setClosetItems]       = useState<ClothingItem[]>([]);
  const [bodyMeasurements, setBodyMeasurements] = useState<BodyMeasurement[]>([]);
  const [analysis, setAnalysis]             = useState<FitAnalysisResult | null>(null);
  const [selectedItemId, setSelectedItemId] = useState<string>("");
  const [selectedSize, setSelectedSize]     = useState<string>("M");
  const [loadError, setLoadError]           = useState("");
  const [isLoading, setIsLoading]           = useState(true);

  const today = new Date().toLocaleDateString("ko-KR", { year: "numeric", month: "long", day: "numeric" });

  const loadItems = useCallback(async () => {
    try {
      const [items, measurements] = await Promise.all([
        api<ClothingItem[]>("/clothing-items"),
        api<BodyMeasurement[]>("/body-measurements"),
      ]);
      setClosetItems(Array.isArray(items) ? items : []);
      setBodyMeasurements(Array.isArray(measurements) ? measurements : []);
      if (Array.isArray(items) && items.length > 0) {
        setSelectedItemId(prev => prev || items[0].id);
      }
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : "데이터 로드 실패");
    }
  }, []);

  const loadAnalysis = useCallback(async () => {
    try {
      const results = await api<FitAnalysisResult[]>("/fit-analysis-results/recent");
      if (Array.isArray(results) && results.length > 0) {
        setAnalysis(results[0]);
        setSelectedSize(results[0].recommended_size_label ?? "M");
      }
    } catch {
      // Analysis may not exist — not fatal
    } finally {
      setIsLoading(false);
    }
  }, []);

  const refreshAll = useCallback(async () => {
    await loadItems();
    await loadAnalysis();
  }, [loadItems, loadAnalysis]);

  useEffect(() => {
    void (async () => {
      setIsLoading(true);
      await refreshAll();
    })();
  }, [refreshAll]);

  const selectedItem = closetItems.find(i => i.id === selectedItemId) ?? null;
  const latestMeasurement = bodyMeasurements[0] ?? null;
  const fitScore          = analysis?.fit_score ?? 0;
  const formattedFitScore = formatFitScore(fitScore);
  const fitLabel          = analysis?.fit_label ?? "";
  const fitComment        = analysis?.fit_comment ?? "";
  const recommendedSizeLabel = analysis?.recommended_size_label ?? "M";
  const confidencePct     = confidenceToPct(analysis?.recommendation_confidence);
  const fitParts          = Object.entries(analysis?.result_details?.partStatuses ?? {});
  const diffs             = analysis?.result_details?.diffs ?? {};

  const fitData3D = useMemo<Body3DFitData | null>(
    () => buildFitData(analysis?.result_details?.partStatuses, analysis?.result_details?.diffs ?? {}),
    [analysis],
  );
  const body3DMeasurements = useMemo<Body3DMeasurements | null>(
    () => latestMeasurement
      ? { height: latestMeasurement.height_cm, chest: latestMeasurement.chest_circumference }
      : null,
    [latestMeasurement],
  );

  if (isLoading) {
    return (
      <main>
        <TopBar />
        <div style={{ padding: "120px 48px", textAlign: "center" }}>
          <div className="eyebrow" style={{ marginBottom: 16 }}>COORDIT FIT FORENSICS · LOADING</div>
          <div style={{ fontFamily: "var(--font-display)", fontStyle: "italic", fontSize: 32, color: "var(--text-muted)" }}>
            분석 데이터를 불러오는 중…
          </div>
        </div>
        <Footer />
      </main>
    );
  }

  return (
    <main>
      <TopBar />

      {/* ── Error Banner ── */}
      {loadError && (
        <div style={{ padding: "12px 48px", background: "rgba(168,66,58,0.08)", borderBottom: "1px solid rgba(168,66,58,0.2)" }}>
          <span style={{ fontSize: 13, color: "var(--fit-tight)", fontFamily: "var(--font-korean)" }}>{loadError}</span>
          <button onClick={() => setLoadError("")} style={{ marginLeft: 12, background: "none", border: "none", cursor: "pointer", fontSize: 12, color: "var(--text-muted)" }}>✕</button>
        </div>
      )}

      {/* ── 1. MySizePanel ── */}
      <MySizePanel onSaved={refreshAll} />

      {/* ── 2. Hero ── */}
      <section style={{ padding: "56px 48px 32px", maxWidth: 1600, margin: "0 auto" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 24 }}>
          <div className="eyebrow">
            COORDIT FIT FORENSICS · {(selectedItem?.name ?? "SELECT ITEM").toUpperCase()}
          </div>
          <div className="eyebrow" style={{ display: "flex", gap: 16 }}>
            <span>{today}</span>
            <span style={{ color: "var(--camel)" }}>· LIVE SCAN</span>
          </div>
        </div>
        <h1 style={{
          margin: 0,
          fontSize: 128,
          fontWeight: 400,
          lineHeight: 1,
          letterSpacing: "-0.04em",
          fontFamily: "var(--font-korean-display)",
        }}>
          핏을,{" "}
          <em style={{ fontFamily: "var(--font-display)", fontStyle: "italic", color: "var(--walnut)" }}>해부</em>
          합니다.
        </h1>
        <p className="korean-sans" style={{ marginTop: 24, fontSize: 18, color: "var(--text-muted)", lineHeight: 1.6, maxWidth: 640 }}>
          당신의 실측 체형 데이터와 브랜드 사이즈 표를 AI가 교차 분석합니다. ±0.3cm의 정밀도로.
        </p>
      </section>

      {/* ── 3. Forensic Scan Panel ── */}
      <section style={{ padding: "0 48px 40px", maxWidth: 1600, margin: "0 auto" }}>
        <div style={{
          display: "grid",
          gridTemplateColumns: "1.3fr 1fr",
          background: "var(--obsidian)",
          borderRadius: 4,
          overflow: "hidden",
          minHeight: 600,
        }}>
          {/* Left Panel — Silhouette */}
          <div style={{
            position: "relative",
            background: "#0a0908",
            overflow: "hidden",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}>
            {/* Blueprint grid */}
            <div style={{
              position: "absolute",
              inset: 0,
              backgroundImage: `
                linear-gradient(rgba(180,138,91,0.04) 1px, transparent 1px),
                linear-gradient(90deg, rgba(180,138,91,0.04) 1px, transparent 1px),
                linear-gradient(rgba(180,138,91,0.08) 1px, transparent 1px),
                linear-gradient(90deg, rgba(180,138,91,0.08) 1px, transparent 1px)
              `,
              backgroundSize: "20px 20px, 20px 20px, 100px 100px, 100px 100px",
            }} />
            {/* Radial glow */}
            <div style={{
              position: "absolute",
              inset: 0,
              background: "radial-gradient(ellipse 60% 70% at 50% 40%, rgba(176,138,91,0.06) 0%, transparent 70%)",
            }} />

            {/* 3D Mannequin */}
            <Body3D fitData={fitData3D} measurements={body3DMeasurements} />

            {/* Scan line */}
            <div style={{
              position: "absolute",
              left: "10%",
              right: "10%",
              height: 1,
              background: "linear-gradient(90deg, transparent, #D4B896, transparent)",
              opacity: 0.6,
              boxShadow: "0 0 12px #D4B896",
              animation: "coordit-scan 4s ease-in-out infinite",
              top: "50%",
              zIndex: 2,
            }} />

            {/* Corner marks */}
            <CornerMark top={0} left={0} />
            <CornerMark top={0} right={0} />
            <CornerMark bottom={0} left={0} />
            <CornerMark bottom={0} right={0} />

            {/* Top-left label */}
            <div style={{
              position: "absolute",
              top: 24,
              left: 24,
              zIndex: 3,
            }}>
              <div style={{ fontSize: 9, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.15em", color: "rgba(176,138,91,0.6)", textTransform: "uppercase" }}>GARMENT</div>
              <div style={{ fontSize: 14, fontFamily: "var(--font-korean)", color: "var(--ivory)", marginTop: 4, fontWeight: 500 }}>
                {selectedItem?.name ?? "—"}
              </div>
              <div style={{ fontSize: 11, fontFamily: "JetBrains Mono, monospace", color: "rgba(245,240,230,0.5)", marginTop: 2 }}>
                SIZE {selectedItem?.size_label ?? selectedSize}
              </div>
            </div>

            {/* Top-right badge */}
            <div style={{
              position: "absolute",
              top: 24,
              right: 24,
              display: "flex",
              alignItems: "center",
              gap: 6,
              padding: "5px 10px",
              border: "1px solid rgba(176,138,91,0.3)",
              borderRadius: 2,
              zIndex: 3,
            }}>
              <div style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--fit-perfect)" }} />
              <span style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", color: "rgba(245,240,230,0.7)", letterSpacing: "0.12em" }}>LIVE · ±0.3cm</span>
            </div>

            {/* Bottom caption */}
            <div style={{
              position: "absolute",
              bottom: 28,
              left: 0,
              right: 0,
              textAlign: "center",
              zIndex: 3,
            }}>
              <em style={{ fontFamily: "var(--font-display)", fontStyle: "italic", fontSize: 52, color: "rgba(176,138,91,0.25)", letterSpacing: "-0.02em", fontWeight: 400 }}>
                A body, mapped.
              </em>
            </div>
          </div>

          {/* Right Panel — Verdict */}
          <div style={{
            padding: "36px 40px",
            display: "flex",
            flexDirection: "column",
            gap: 28,
            color: "var(--ivory)",
          }}>
            {/* Verdict header */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.15em", color: "rgba(245,240,230,0.5)" }}>
                ✦ COORDIT AI · VERDICT
              </div>
              {fitScore > 0 && analysis && (
                <div style={{
                  padding: "5px 12px",
                  background: scoreColor(fitScore),
                  borderRadius: 2,
                  fontSize: 10,
                  fontFamily: "JetBrains Mono, monospace",
                  letterSpacing: "0.12em",
                  color: "var(--ivory)",
                }}>
                  {fitLabelToKorean(fitLabel).toUpperCase()} · {formattedFitScore}/100
                </div>
              )}
            </div>

            {/* Main verdict text */}
            <div>
              <h2 className="korean-serif" style={{
                margin: 0,
                fontSize: 44,
                fontWeight: 400,
                lineHeight: 1.2,
                letterSpacing: "-0.02em",
                fontFamily: "var(--font-korean-display)",
                color: "var(--ivory)",
              }}>
                이 옷은 당신에게 Size <span style={{ color: "var(--camel)" }}>{recommendedSizeLabel}</span>으로 완성됩니다.
              </h2>
            </div>

            {/* Recommendation text */}
            <p className="korean-sans" style={{ margin: 0, fontSize: 14, lineHeight: 1.7, color: "rgba(245,240,230,0.75)" }}>
              {fitComment || "아이템을 선택하고 체형 데이터를 입력하면 AI가 최적 사이즈를 분석합니다."}
            </p>

            {/* Confidence bar */}
            <div>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 8 }}>
                <span style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.12em", color: "rgba(245,240,230,0.5)" }}>PREDICTION CONFIDENCE</span>
                <span style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", color: "var(--camel)" }}>{confidencePct}%</span>
              </div>
              <div style={{ height: 3, background: "rgba(245,240,230,0.1)", borderRadius: 2 }}>
                <div style={{
                  height: "100%",
                  width: `${confidencePct}%`,
                  background: "var(--camel)",
                  borderRadius: 2,
                  transition: "width 0.6s ease",
                }} />
              </div>
              <ConfidenceExplanationText result={analysis} />
            </div>

            {/* Item picker */}
            <div>
              <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.12em", color: "rgba(245,240,230,0.5)", marginBottom: 8 }}>
                아이템 선택
              </div>
              <select
                value={selectedItemId}
                onChange={e => setSelectedItemId(e.target.value)}
                style={{
                  width: "100%",
                  padding: "10px 14px",
                  background: "rgba(255,255,255,0.06)",
                  border: "1px solid rgba(245,240,230,0.12)",
                  borderRadius: 2,
                  color: "var(--ivory)",
                  fontFamily: "var(--font-korean)",
                  fontSize: 13,
                  cursor: "pointer",
                  appearance: "none",
                }}
              >
                {closetItems.length === 0 && (
                  <option value="">옷장 아이템 없음</option>
                )}
                {closetItems.map(item => (
                  <option key={item.id} value={item.id}>{item.name}</option>
                ))}
              </select>
            </div>

            {/* Size picker */}
            <div>
              <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.12em", color: "rgba(245,240,230,0.5)", marginBottom: 8 }}>
                사이즈 선택
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                {SIZES.map(sz => {
                  const isSelected = sz === selectedSize;
                  const isAiRec   = analysis !== null && sz === recommendedSizeLabel;
                  return (
                    <button
                      key={sz}
                      onClick={() => setSelectedSize(sz)}
                      style={{
                        position: "relative",
                        flex: 1,
                        padding: "10px 0",
                        background:     isSelected ? "var(--camel)" : "rgba(255,255,255,0.06)",
                        border:         isSelected ? "1px solid var(--camel)" : "1px solid rgba(245,240,230,0.12)",
                        borderRadius:   2,
                        color:          isSelected ? "var(--ivory)" : "rgba(245,240,230,0.6)",
                        fontFamily:     "JetBrains Mono, monospace",
                        fontSize:       12,
                        cursor:         "pointer",
                        transition:     "all 0.2s",
                        letterSpacing:  "0.05em",
                      }}
                    >
                      {sz}
                      {isAiRec && (
                        <span style={{
                          position: "absolute",
                          top: -8,
                          right: 4,
                          fontSize: 8,
                          fontFamily: "JetBrains Mono, monospace",
                          background: "var(--fit-perfect)",
                          color: "var(--ivory)",
                          padding: "1px 4px",
                          borderRadius: 2,
                          letterSpacing: "0.05em",
                        }}>
                          AI
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Action buttons */}
            <div style={{ display: "flex", gap: 10, marginTop: "auto" }}>
              <button className="btn btn-camel" style={{ flex: 1 }}>
                장바구니에 담기
              </button>
              <button
                style={{
                  padding: "14px 18px",
                  background: "transparent",
                  border: "1px solid rgba(245,240,230,0.2)",
                  borderRadius: "var(--radius)",
                  color: "var(--ivory)",
                  fontSize: 18,
                  cursor: "pointer",
                  lineHeight: 1,
                }}
              >
                ♡
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* ── 4. VITALS ── */}
      <section style={{ padding: "0 48px 40px", maxWidth: 1600, margin: "0 auto" }}>
        <div className="eyebrow" style={{ marginBottom: 20 }}>VITALS · 핵심 지표</div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16 }}>
          {/* Card 1 */}
          <div style={{ background: "var(--bg-raised)", border: "1px solid var(--line)", borderRadius: 4, padding: "24px 28px" }}>
            <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.15em", color: "var(--text-muted)", textTransform: "uppercase" }}>OVERALL FIT</div>
            <div style={{ fontSize: 48, fontWeight: 400, lineHeight: 1, marginTop: 12, fontFamily: "var(--font-display)", color: fitScore > 0 ? scoreColor(fitScore) : "var(--obsidian)" }}>
              {fitScore > 0 ? formattedFitScore : "—"}
            </div>
            <div style={{ fontSize: 11, color: "var(--text-muted)", marginTop: 4, fontFamily: "JetBrains Mono, monospace" }}>/100</div>
            <div style={{ fontSize: 11, color: "var(--text-dim)", marginTop: 12, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.08em" }}>Fit Forensics Score</div>
          </div>

          {/* Card 2 */}
          <div style={{ background: "var(--bg-raised)", border: "1px solid var(--line)", borderRadius: 4, padding: "24px 28px" }}>
            <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.15em", color: "var(--text-muted)", textTransform: "uppercase" }}>VERDICT</div>
            <div style={{ fontSize: 36, fontWeight: 400, lineHeight: 1.1, marginTop: 12, fontFamily: "var(--font-display)", fontStyle: "italic", color: "var(--obsidian)" }}>
              {fitLabel ? fitLabelToKorean(fitLabel) : "—"}
            </div>
            <div style={{ fontSize: 11, color: "var(--text-dim)", marginTop: 16, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.08em" }}>종합 핏 판정</div>
          </div>

          {/* Card 3 */}
          <div style={{ background: "var(--bg-raised)", border: "1px solid var(--line)", borderRadius: 4, padding: "24px 28px" }}>
            <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.15em", color: "var(--text-muted)", textTransform: "uppercase" }}>GARMENT</div>
            <div style={{ fontSize: 24, fontWeight: 400, lineHeight: 1.2, marginTop: 12, fontFamily: "var(--font-display)", fontStyle: "italic", color: "var(--camel)" }}>
              {selectedItem?.category ?? "—"}
            </div>
            <div className="korean-sans" style={{ fontSize: 13, marginTop: 8, fontWeight: 500, color: "var(--obsidian)" }}>
              {selectedItem?.name ?? "아이템 미선택"}
            </div>
            <div style={{ fontSize: 11, color: "var(--text-dim)", marginTop: 8, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.08em" }}>{selectedItem?.brand ?? ""}</div>
          </div>

          {/* Card 4 — obsidian */}
          <div style={{ background: "var(--obsidian)", border: "1px solid var(--obsidian)", borderRadius: 4, padding: "24px 28px", color: "var(--ivory)" }}>
            <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.15em", color: "rgba(245,240,230,0.5)", textTransform: "uppercase" }}>CONFIDENCE</div>
            <div style={{ fontSize: 48, fontWeight: 400, lineHeight: 1, marginTop: 12, fontFamily: "var(--font-display)", color: "var(--camel)" }}>
              {confidencePct > 0 ? `${confidencePct}%` : "—"}
            </div>
            <div style={{ fontSize: 11, color: "rgba(245,240,230,0.5)", marginTop: 12, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.08em" }}>예측 신뢰도</div>
            <ConfidenceExplanationText result={analysis} tone="dark" />
          </div>
        </div>
      </section>

      {/* ── 5. SCORE BREAKDOWN ── */}
      {fitParts.length > 0 && (
        <section style={{ padding: "0 48px 40px", maxWidth: 1600, margin: "0 auto" }}>
          <div style={{ background: "var(--bg-raised)", border: "1px solid var(--line)", borderRadius: 4, overflow: "hidden" }}>
            {/* Header */}
            <div style={{ padding: "20px 28px", borderBottom: "1px solid var(--line)", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <div className="eyebrow">SCORE BREAKDOWN · 가중치 기반 분석</div>
              <div style={{ display: "flex", gap: 20, fontSize: 10, fontFamily: "JetBrains Mono, monospace" }}>
                {([
                  { label: "Perfect", color: "var(--fit-perfect)" },
                  { label: "Caution", color: "var(--camel)" },
                  { label: "Issue",   color: "var(--fit-tight)" },
                ] as const).map(({ label, color }) => (
                  <div key={label} style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <div style={{ width: 8, height: 8, borderRadius: "50%", background: color }} />
                    <span style={{ color: "var(--text-muted)" }}>{label}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Rows */}
            <div style={{ padding: "8px 0" }}>
              {fitParts.map(([key, status], partIdx) => {
                const partScore = partStatusToScore(status);
                const color     = partStatusToColor(status);
                const diffVal   = diffs[key];
                const partName  = PART_NAMES[key] ?? key;

                return (
                  <div key={key} style={{
                    display: "grid",
                    gridTemplateColumns: "120px 1fr 56px 110px 1fr",
                    alignItems: "center",
                    gap: 16,
                    padding: "12px 28px",
                    borderBottom: "1px solid var(--line)",
                  }}>
                    <div className="korean-sans" style={{ fontSize: 13, fontWeight: 500 }}>{partName}</div>
                    <div style={{ height: 4, background: "var(--linen)", borderRadius: 2 }}>
                      <div style={{ height: "100%", width: `${partScore}%`, background: color, borderRadius: 2 }} />
                    </div>
                    <div style={{ fontSize: 13, fontFamily: "JetBrains Mono, monospace", color, textAlign: "right" }}>{partScore}</div>
                    <div style={{
                      padding: "3px 8px",
                      background: color === "var(--fit-perfect)" ? "rgba(91,115,85,0.12)" : color === "var(--camel)" ? "rgba(176,138,91,0.12)" : "rgba(168,66,58,0.12)",
                      border: `1px solid ${color === "var(--fit-perfect)" ? "rgba(91,115,85,0.3)" : color === "var(--camel)" ? "rgba(176,138,91,0.3)" : "rgba(168,66,58,0.3)"}`,
                      borderRadius: 2,
                      fontSize: 10,
                      fontFamily: "JetBrains Mono, monospace",
                      color,
                      textAlign: "center" as const,
                    }}>
                      {Number.isFinite(diffVal) ? `${diffVal > 0 ? "+" : ""}${diffVal.toFixed(1)}cm` : status.replace(/_/g, " ")}
                    </div>
                    <div style={{ fontSize: 12, color: "var(--text-muted)", fontFamily: "var(--font-korean)" }}>
                      {analysis?.result_details?.partExplanations?.[partIdx] ?? "—"}
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Footer */}
            <div style={{ padding: "20px 28px", borderTop: "1px solid var(--line)", display: "flex", alignItems: "center", gap: 20 }}>
              <div style={{ flex: 1, height: 6, background: "var(--linen)", borderRadius: 3 }}>
                <div style={{ height: "100%", width: `${fitScore}%`, background: scoreColor(fitScore), borderRadius: 3 }} />
              </div>
              <div style={{ fontSize: 24, fontFamily: "var(--font-display)", fontWeight: 500, color: scoreColor(fitScore) }}>{formattedFitScore}</div>
              <div className="korean-sans" style={{ fontSize: 13, color: "var(--text-muted)" }}>
                {fitLabelToKorean(fitLabel)}
              </div>
            </div>
          </div>
        </section>
      )}

      {/* ── 6. DETAILED TABLE ── */}
      <section style={{ padding: "0 48px 40px", maxWidth: 1600, margin: "0 auto" }}>
        <div className="eyebrow" style={{ marginBottom: 20 }}>DETAILED ANALYSIS · 측정값 비교표</div>
        <div style={{ background: "var(--bg-raised)", border: "1px solid var(--line)", borderRadius: 4, overflow: "hidden" }}>
          {/* Table header */}
          <div style={{
            display: "grid",
            gridTemplateColumns: "1.2fr 1fr 1fr 80px 120px 100px",
            gap: 16,
            padding: "14px 24px",
            background: "var(--linen)",
            borderBottom: "1px solid var(--line)",
            fontSize: 10,
            fontFamily: "JetBrains Mono, monospace",
            letterSpacing: "0.1em",
            textTransform: "uppercase",
            color: "var(--text-muted)",
          }}>
            <div>측정 부위</div>
            <div>내 사이즈</div>
            <div>가먼트 ({selectedSize})</div>
            <div>Δ</div>
            <div>상태</div>
            <div>신뢰도</div>
          </div>

          {/* Rows */}
          {DETAIL_ROWS.map(({ part, bodyKey, diffKey }) => {
            const myVal  = bodyKey && latestMeasurement ? latestMeasurement[bodyKey] : undefined;
            const diffVal = diffKey ? diffs[diffKey] : undefined;
            const myNumber = typeof myVal === "number" && Number.isFinite(myVal) ? myVal : null;
            const diffNumber = typeof diffVal === "number" && Number.isFinite(diffVal) ? diffVal : null;
            const garmentVal = myNumber !== null && diffNumber !== null
              ? (myNumber + diffNumber).toFixed(1)
              : "—";

            const statusEntry = diffKey ? analysis?.result_details?.partStatuses?.[diffKey] : undefined;
            const statusColor = statusEntry ? partStatusToColor(statusEntry) : "var(--text-muted)";

            return (
              <div key={part} style={{
                display: "grid",
                gridTemplateColumns: "1.2fr 1fr 1fr 80px 120px 100px",
                gap: 16,
                padding: "14px 24px",
                borderBottom: "1px solid var(--line)",
                alignItems: "center",
              }}>
                <div className="korean-sans" style={{ fontSize: 13 }}>{part}</div>
                <div style={{ fontFamily: "JetBrains Mono, monospace", fontSize: 13 }}>
                  {Number.isFinite(myVal) ? `${myVal}cm` : "—"}
                </div>
                <div style={{ fontFamily: "JetBrains Mono, monospace", fontSize: 13, color: "var(--text-muted)" }}>
                  {garmentVal !== "—" ? `${garmentVal}cm` : "—"}
                </div>
                <div style={{ fontFamily: "JetBrains Mono, monospace", fontSize: 13, color: diffNumber !== null ? (diffNumber >= 0 ? "var(--fit-perfect)" : "var(--fit-tight)") : "var(--text-dim)" }}>
                  {diffNumber !== null ? `${diffNumber > 0 ? "+" : ""}${diffNumber.toFixed(1)}` : "—"}
                </div>
                <div style={{ fontSize: 11, fontFamily: "JetBrains Mono, monospace", color: statusColor, letterSpacing: "0.06em" }}>
                  {statusEntry ? statusEntry.replace(/_/g, " ") : "—"}
                </div>
                <div style={{ fontSize: 11, fontFamily: "JetBrains Mono, monospace", color: "var(--text-dim)" }}>
                  {analysis?.recommendation_confidence ?? "—"}
                </div>
              </div>
            );
          })}

          {/* AI Note */}
          <div style={{ padding: "16px 24px", background: "rgba(176,138,91,0.04)", borderTop: "1px solid var(--line)" }}>
            <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.12em", color: "var(--camel)", marginBottom: 6 }}>AI NOTE</div>
            <p className="korean-sans" style={{ margin: 0, fontSize: 13, color: "var(--text-muted)", lineHeight: 1.6 }}>
              {analysis?.fit_comment || "아이템을 선택하면 AI 분석 코멘트가 표시됩니다."}
            </p>
          </div>
        </div>
      </section>

      {/* ── 7. RELATED TRY-ONS ── */}
      <section style={{ padding: "0 48px 80px", maxWidth: 1600, margin: "0 auto" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 20 }}>
          <div className="eyebrow">RELATED TRY-ONS · 추천 아이템</div>
          <button
            onClick={() => router.push("/closet")}
            style={{ background: "none", border: "none", cursor: "pointer", fontSize: 12, fontFamily: "JetBrains Mono, monospace", color: "var(--text-muted)", letterSpacing: "0.08em" }}
          >
            VIEW ALL →
          </button>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 20 }}>
          {RELATED_ITEMS.map((item) => {
            const scoreClr = scoreColor(item.score);
            const fitBg = item.fitLabel === "Perfect" ? "rgba(91,115,85,0.85)"
              : item.fitLabel === "Loose"   ? "rgba(122,111,160,0.85)"
              : "rgba(168,66,58,0.85)";
            return (
              <div key={item.name} style={{ background: "var(--bg-raised)", border: "1px solid var(--line)", borderRadius: 4, overflow: "hidden" }}>
                <div style={{ position: "relative", aspectRatio: "4/5", overflow: "hidden" }}>
                  <img
                    src={item.img}
                    alt={item.name}
                    style={{ width: "100%", height: "100%", objectFit: "cover" }}
                  />
                  {/* FIT badge */}
                  <div style={{
                    position: "absolute",
                    top: 12,
                    left: 12,
                    padding: "4px 10px",
                    background: fitBg,
                    backdropFilter: "blur(8px)",
                    borderRadius: 2,
                    fontSize: 9,
                    fontFamily: "JetBrains Mono, monospace",
                    letterSpacing: "0.12em",
                    color: "var(--ivory)",
                  }}>
                    FIT · {item.fitLabel.toUpperCase()}
                  </div>
                  {/* Size */}
                  <div style={{
                    position: "absolute",
                    bottom: 12,
                    right: 12,
                    fontFamily: "var(--font-display)",
                    fontStyle: "italic",
                    fontSize: 32,
                    color: "rgba(245,240,230,0.85)",
                    lineHeight: 1,
                    textShadow: "0 2px 8px rgba(0,0,0,0.4)",
                  }}>
                    {item.size}
                  </div>
                </div>
                <div style={{ padding: "14px 16px" }}>
                  <div className="korean-sans" style={{ fontSize: 13, fontWeight: 500 }}>{item.name}</div>
                  <div style={{ marginTop: 10 }}>
                    <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                      <span style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", color: "var(--text-dim)" }}>FIT SCORE</span>
                      <span style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", color: scoreClr }}>{formatFitScore(item.score)}</span>
                    </div>
                    <div style={{ height: 3, background: "var(--linen)", borderRadius: 2 }}>
                      <div style={{ height: "100%", width: `${item.score}%`, background: scoreClr, borderRadius: 2 }} />
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      <Footer />
    </main>
  );
}
