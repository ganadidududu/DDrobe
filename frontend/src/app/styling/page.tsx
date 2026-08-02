"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Footer } from "../../components/Footer";
import { TopBar } from "../../components/TopBar";
import { api } from "../../lib/api";
import { formatFitScore } from "../../lib/fit-score";

// ─── Types ────────────────────────────────────────────────────────────

interface StylingLook {
  id?: string;
  name: string;
  name_ko: string;
  mood: string;
  palette: string[];
  ai_reasoning: string;
  fit_score?: number;
  item_ids?: string[];
}

interface ClothingItem {
  id: string;
  name: string;
  category: string;
  image_url?: string;
  raw_product_data?: Record<string, unknown>;
}

// ─── Constants ────────────────────────────────────────────────────────

const PLACEHOLDER_ITEMS: ClothingItem[] = [
  { id: "ph-1", name: "헤리티지 카멜 코트",       category: "아우터" },
  { id: "ph-2", name: "에센셜 피마 티셔츠",        category: "이너"   },
  { id: "ph-3", name: "프리시전 플리츠 트라우저",  category: "하의"   },
  { id: "ph-4", name: "에센셜 화이트 스니커즈",    category: "슈즈"   },
];

const FALLBACK_COORDS: StylingLook[] = [
  {
    name: "Parisian Weekday",
    name_ko: "파리지엔 워크데이",
    mood: "비즈니스 · 비 예보",
    palette: ["#8F6F45", "#F5F0E6", "#2D2A27"],
    ai_reasoning: "옷장 아이템으로 비즈니스 코디를 추천합니다. AI 코디 생성 버튼을 눌러보세요.",
    fit_score: 88,
  },
  {
    name: "Obsidian Evening",
    name_ko: "옵시디언 이브닝",
    mood: "디너 · 실내",
    palette: ["#1C1B1A", "#4A3826", "#D4B896"],
    ai_reasoning: "저녁 행사에 맞는 포멀한 코디입니다.",
    fit_score: 85,
  },
  {
    name: "Weekend Essai",
    name_ko: "주말의 에세이",
    mood: "캐주얼 · 주말",
    palette: ["#E8DFC9", "#B08A5B", "#5A6B7E"],
    ai_reasoning: "주말에 어울리는 편안한 코디입니다.",
    fit_score: 82,
  },
];

const QUICK_CHIPS = [
  "내일 미팅",
  "주말 브런치",
  "파리 출장 3일",
  "첫 소개팅",
  "결혼식 하객",
  "갤러리 오프닝",
];

const ITEM_ROLES = ["HERO", "BASE", "STRUCTURE", "ACCENT"] as const;

const TIME_SLOTS = [
  { name: "Morning Meeting", tag: "BIZ CASUAL",   time: "08:30", color: "#8F6F45" },
  { name: "Cafe Lunch",      tag: "SMART CASUAL", time: "12:30", color: "#D4B896" },
  { name: "Client Dinner",   tag: "ELEVATED",     time: "19:00", color: "#1C1B1A" },
  { name: "Weekend Walk",    tag: "EFFORTLESS",   time: "SAT",   color: "#5A6B7E" },
];

// ─── Sub-components (module scope) ────────────────────────────────────

function StatCard({
  eyebrow,
  value,
  unit,
  subtitle,
  note,
  valueColor,
  progress,
  progressColor,
}: {
  eyebrow: string;
  value: string | number;
  unit?: string;
  subtitle: string;
  note: string;
  valueColor?: string;
  progress?: number;
  progressColor?: string;
}) {
  return (
    <div style={{
      background: "var(--bg-raised)",
      border: "1px solid var(--line)",
      borderRadius: 4,
      padding: "24px 28px",
    }}>
      <div className="eyebrow" style={{ marginBottom: 12 }}>{eyebrow}</div>
      <div style={{
        fontFamily: "var(--font-display)",
        fontSize: 48,
        fontWeight: 500,
        letterSpacing: "-0.03em",
        lineHeight: 1,
        color: valueColor || "var(--obsidian)",
      }}>
        {value}
        {unit && (
          <span style={{ fontSize: 18, color: "var(--text-muted)", marginLeft: 4, fontFamily: "var(--font-display)" }}>
            {unit}
          </span>
        )}
      </div>
      <div className="korean-sans" style={{ fontSize: 13, color: "var(--text-muted)", marginTop: 8 }}>
        {subtitle}
      </div>
      {progress !== undefined && progressColor && (
        <div style={{ height: 3, background: "var(--linen)", borderRadius: 2, marginTop: 12, overflow: "hidden" }}>
          <div style={{ height: "100%", width: `${progress}%`, background: progressColor, borderRadius: 2, transition: "width 0.6s ease" }} />
        </div>
      )}
      <div style={{ fontSize: 11, color: "var(--text-dim)", marginTop: 8, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.08em" }}>
        {note}
      </div>
    </div>
  );
}

function ItemCard({
  item,
  role,
  palette,
  isDark,
  index,
}: {
  item: ClothingItem;
  role: string;
  palette: string[];
  isDark: boolean;
  index: number;
}) {
  const bg = palette[index % palette.length] || "#8F6F45";
  const textColor = isDark ? "var(--ivory)" : "var(--obsidian)";

  return (
    <div style={{
      borderRadius: 2,
      overflow: "hidden",
      position: "relative",
      aspectRatio: "1/1",
      display: "flex",
      flexDirection: "column",
      justifyContent: "flex-end",
      padding: 16,
      background: bg,
    }}>
      {item.image_url && (
        <img
          src={item.image_url}
          alt={item.name}
          style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }}
        />
      )}
      {/* Gradient overlay */}
      <div style={{
        position: "absolute",
        inset: 0,
        background: "linear-gradient(to top, rgba(0,0,0,0.5) 0%, transparent 60%)",
      }} />
      {/* Role badge */}
      <div style={{
        position: "absolute",
        top: 10,
        left: 10,
        fontSize: 9,
        fontFamily: "JetBrains Mono, monospace",
        letterSpacing: "0.12em",
        color: "rgba(245,240,230,0.75)",
        background: "rgba(0,0,0,0.35)",
        padding: "3px 7px",
        borderRadius: 2,
      }}>
        {role}
      </div>
      {/* Item info */}
      <div style={{ position: "relative", zIndex: 1 }}>
        <div className="korean-sans" style={{ fontSize: 12, fontWeight: 500, color: "var(--ivory)", lineHeight: 1.3 }}>
          {item.name}
        </div>
        <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.1em", color: "rgba(245,240,230,0.6)", marginTop: 3 }}>
          {item.category.toUpperCase()}
        </div>
      </div>
    </div>
  );
}

function TimeSlotCard({ slot }: { slot: typeof TIME_SLOTS[number] }) {
  return (
    <div style={{
      background: "var(--bg-raised)",
      border: "1px solid var(--line)",
      borderRadius: 4,
      overflow: "hidden",
    }}>
      <div style={{ height: 8, background: slot.color }} />
      <div style={{ padding: 20 }}>
        <div style={{ fontFamily: "var(--font-display)", fontStyle: "italic", fontSize: 18, fontWeight: 500, letterSpacing: "-0.01em" }}>
          {slot.name}
        </div>
        <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.12em", color: "var(--text-muted)", marginTop: 6 }}>
          {slot.tag}
        </div>
        <div style={{ fontSize: 13, fontFamily: "JetBrains Mono, monospace", color: "var(--text-dim)", marginTop: 10 }}>
          {slot.time}
        </div>
      </div>
    </div>
  );
}

// ─── Styling Page ──────────────────────────────────────────────────────

function normalizeLook(look: StylingLook): StylingLook {
  let palette: string[];
  let item_ids: string[] | undefined;
  try { palette = typeof look.palette === "string" ? (JSON.parse(look.palette) as string[]) : (look.palette ?? []); }
  catch { palette = []; }
  try { item_ids = typeof look.item_ids === "string" ? (JSON.parse(look.item_ids) as string[]) : look.item_ids; }
  catch { item_ids = []; }
  return { ...look, palette, item_ids, fit_score: Number.isFinite(Number(look.fit_score)) ? Number(look.fit_score) : undefined };
}

export default function StylingPage() {
  const [prompt, setPrompt] = useState("내일 오후 2시 파트너사 미팅. 비 예보 있음.");
  const [activeCoord, setActiveCoord] = useState(0);
  const [coords, setCoords] = useState<StylingLook[]>([]);
  const [closetItems, setClosetItems] = useState<ClothingItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [generated, setGenerated] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState("");

  // ── Initial load ────────────────────────────────────────────────────
  useEffect(() => {
    (async () => {
      try {
        const saved = await api<StylingLook[]>("/styling/saved");
        if (Array.isArray(saved) && saved.length > 0) {
          setCoords(saved.map(normalizeLook));
          setGenerated(true);
        }
      } catch { /* non-fatal — backend route not yet available */ }

      try {
        const items = await api<ClothingItem[]>("/clothing-items");
        if (Array.isArray(items)) setClosetItems(items);
      } catch { /* non-fatal */ }

      setInitialLoading(false);
    })();
  }, []);

  // ── Generate ────────────────────────────────────────────────────────
  const generate = useCallback(async () => {
    setLoading(true);
    setSaveError("");
    try {
      const res = await api<{ looks: StylingLook[]; closetItems: ClothingItem[] }>(
        "/styling/generate",
        { method: "POST", body: { prompt } }
      );
      setCoords((res.looks ?? []).map(normalizeLook));
      if (Array.isArray(res.closetItems)) setClosetItems(res.closetItems);
      setGenerated(true);
      setActiveCoord(0);
    } catch {
      setSaveError("AI 코디 생성 기능은 백엔드 연동 후 이용 가능합니다.");
    } finally {
      setLoading(false);
    }
  }, [prompt]);

  // ── Save look ───────────────────────────────────────────────────────
  const saveLook = useCallback(async (id: string | undefined) => {
    if (!id || saving) return;
    setSaving(true);
    setSavedMsg("");
    try {
      await api(`/styling/${id}/save`, { method: "POST" });
      setSavedMsg("저장됨 ✓");
      setTimeout(() => setSavedMsg(""), 2500);
    } catch {
      setSaveError("코디 저장 기능은 백엔드 연동 후 이용 가능합니다.");
    } finally {
      setSaving(false);
    }
  }, [saving]);

  // ── Derived ─────────────────────────────────────────────────────────
  const displayCoords = useMemo(
    () => (coords.length > 0 ? coords : FALLBACK_COORDS),
    [coords]
  );

  // W2: clamp activeCoord when displayCoords shrinks
  useEffect(() => {
    if (activeCoord >= displayCoords.length) setActiveCoord(0);
  }, [displayCoords.length, activeCoord]);

  const c = displayCoords[activeCoord] ?? displayCoords[0];

  const lookItems = useMemo(() => {
    if (!c?.item_ids?.length) return [];
    return c.item_ids
      .map(id => closetItems.find(i => i.id === id))
      .filter((i): i is ClothingItem => i !== undefined);
  }, [c, closetItems]);

  const displayItems = lookItems.length > 0 ? lookItems : PLACEHOLDER_ITEMS;

  const isDark = activeCoord === 0;
  const lookNum = String(activeCoord + 1).padStart(2, "0");

  const reasoningRows = useMemo(() => {
    if (generated && c?.ai_reasoning) {
      return [
        { label: "AI 큐레이션",  detail: c.ai_reasoning,                                         tag: "AI"      },
        { label: "TPO 문맥",     detail: `"${prompt}" 컨텍스트에 최적화`,                          tag: "CONTEXT" },
        { label: "아이템 구성",  detail: `${displayItems.length}개 옷장 아이템`,                   tag: "ITEMS"   },
        { label: "핏 스코어",    detail: `체형 기반 핏 점수: ${formatFitScore(c.fit_score ?? 85)}점`, tag: "FIT"     },
      ];
    }
    return [
      { label: "색상 조화",   detail: "유사 색상군 내 콘트라스트 레이어링 적용",   tag: "COLOR"   },
      { label: "TPO 문맥",    detail: "비즈니스 캐주얼 드레스 코드 최적화",        tag: "CONTEXT" },
      { label: "소재 믹싱",   detail: "울 · 코튼 레이어링으로 온도 조절",          tag: "FABRIC"  },
      { label: "핏 밸런스",   detail: "오버사이즈 상의 · 슬림 하의 실루엣",        tag: "FIT"     },
    ];
  }, [generated, c, prompt, displayItems.length]);

  return (
    <main>
      <TopBar />

      {/* ── 1. Header ─────────────────────────────────────────────── */}
      <section style={{ padding: "48px 48px 0", maxWidth: 1600, margin: "0 auto" }}>
        <div className="eyebrow" style={{ marginBottom: 20 }}>AI STYLIST · TPO ENGINE</div>
        <div style={{ display: "grid", gridTemplateColumns: "1.2fr 1fr", gap: 48, alignItems: "flex-end" }}>
          <h1 style={{
            margin: 0,
            fontSize: 88,
            fontFamily: "var(--font-korean-display)",
            fontWeight: 400,
            letterSpacing: "-0.03em",
            lineHeight: 0.95,
          }}>
            당신의 순간을<br />
            <span style={{ fontFamily: "var(--font-display)", fontStyle: "italic", color: "var(--walnut)" }}>큐레이팅</span>합니다.
          </h1>
          <div>
            <div style={{ fontSize: 10, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.16em", color: "var(--text-dim)", marginBottom: 16 }}>
              POWERED BY CLAUDE · OPUS
            </div>
            <p className="korean-sans" style={{ margin: 0, fontSize: 14, lineHeight: 1.75, color: "var(--text-muted)", maxWidth: 380 }}>
              AI가 당신의 옷장 데이터, 체형 프로필, 그리고 TPO 컨텍스트를 분석해 최적의 코디를 큐레이션합니다. 매일 새로운 스타일 에디션을 경험하세요.
            </p>
          </div>
        </div>
      </section>

      {/* ── 2. Prompt bar ─────────────────────────────────────────── */}
      <section style={{ padding: "40px 48px 0", maxWidth: 1600, margin: "0 auto" }}>
        <div style={{
          background: "var(--bg-raised)",
          border: "1px solid var(--line)",
          borderRadius: 4,
          padding: "20px 24px",
        }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <span style={{ fontSize: 18, color: "var(--camel)", flexShrink: 0 }}>✦</span>
            <input
              type="text"
              value={prompt}
              onChange={e => setPrompt(e.target.value)}
              placeholder="오늘의 TPO를 입력하세요..."
              style={{
                flex: 1,
                border: "none",
                background: "transparent",
                outline: "none",
                fontSize: 15,
                fontFamily: "var(--font-korean)",
                color: "var(--obsidian)",
                letterSpacing: "0.01em",
              }}
            />
            <button
              className="btn btn-primary"
              onClick={generate}
              disabled={loading}
              style={{ flexShrink: 0, opacity: loading ? 0.7 : 1, fontSize: 13 }}
            >
              {loading ? "✦ AI 분석중..." : "AI 코디 생성"}
            </button>
          </div>

          {/* Quick chips */}
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 16, paddingTop: 16, borderTop: "1px solid var(--line)" }}>
            {QUICK_CHIPS.map(chip => (
              <button
                key={chip}
                onClick={() => setPrompt(chip)}
                style={{
                  borderRadius: 999,
                  padding: "6px 14px",
                  background: "var(--bg-raised)",
                  border: "1px solid var(--line)",
                  fontSize: 12,
                  fontFamily: "JetBrains Mono, monospace",
                  cursor: "pointer",
                  color: "var(--text-muted)",
                  transition: "all 0.15s",
                }}
              >
                {chip}
              </button>
            ))}
          </div>
        </div>

        {/* Error notice */}
        {saveError && (
          <div style={{
            marginTop: 12,
            padding: "10px 14px",
            background: "rgba(168,66,58,0.08)",
            border: "1px solid rgba(168,66,58,0.2)",
            borderRadius: 4,
            fontSize: 13,
            color: "var(--fit-tight)",
            fontFamily: "var(--font-korean)",
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}>
            {saveError}
            <button
              onClick={() => setSaveError("")}
              style={{ background: "none", border: "none", cursor: "pointer", fontSize: 12, color: "var(--text-muted)" }}
            >
              ✕
            </button>
          </div>
        )}
      </section>

      {/* ── 3. Info strip ─────────────────────────────────────────── */}
      <section style={{ padding: "32px 48px 0", maxWidth: 1600, margin: "0 auto" }}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 16 }}>
          <StatCard
            eyebrow="TODAY"
            value="18"
            unit="°C"
            subtitle="구름 조금"
            note="린넨·울 레이어링 추천"
          />
          <StatCard
            eyebrow="STYLE DNA"
            value="88"
            unit="/100"
            subtitle="시너지 스코어"
            note="옷장 아이템 매칭률 기준"
            valueColor="var(--walnut)"
            progress={88}
            progressColor="var(--walnut)"
          />
          <StatCard
            eyebrow="WARDROBE UTILIZATION"
            value="94"
            unit="%"
            subtitle="이번 주 활용도"
            note="최근 7일 코디 활용률"
            valueColor="var(--fit-perfect)"
            progress={94}
            progressColor="var(--fit-perfect)"
          />
        </div>
      </section>

      {/* ── 4. Coordinate explorer ────────────────────────────────── */}
      <section style={{ padding: "56px 48px 0", maxWidth: 1600, margin: "0 auto" }}>
        {/* Section header */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginBottom: 32 }}>
          <div>
            <div className="eyebrow" style={{ marginBottom: 10 }}>CURATED FOR YOU · 0{displayCoords.length}</div>
            <h2 className="korean-serif" style={{
              margin: 0,
              fontSize: 44,
              fontWeight: 400,
              letterSpacing: "-0.02em",
              fontFamily: "var(--font-korean-display)",
            }}>
              추천 코디
            </h2>
          </div>
          {/* Nav dots */}
          <div style={{ display: "flex", gap: 8 }}>
            {displayCoords.map((_, i) => (
              <button
                key={i}
                onClick={() => setActiveCoord(i)}
                style={{
                  width: 40,
                  height: 40,
                  borderRadius: "50%",
                  border: "1px solid var(--line-strong)",
                  background: activeCoord === i ? "var(--obsidian)" : "transparent",
                  color: activeCoord === i ? "var(--ivory)" : "var(--text-muted)",
                  fontSize: 13,
                  fontFamily: "JetBrains Mono, monospace",
                  cursor: "pointer",
                  transition: "all 0.2s",
                }}
              >
                {i + 1}
              </button>
            ))}
          </div>
        </div>

        {/* Featured look */}
        <div style={{
          display: "grid",
          gridTemplateColumns: "1fr 1.4fr",
          gap: 0,
          borderRadius: 4,
          overflow: "hidden",
          border: "1px solid var(--line)",
        }}>
          {/* Left col — editorial copy */}
          <div style={{
            background: isDark ? "var(--obsidian)" : "var(--bg-raised)",
            color: isDark ? "var(--ivory)" : "var(--obsidian)",
            padding: 40,
            transition: "background 0.35s, color 0.35s",
            display: "flex",
            flexDirection: "column",
            gap: 24,
          }}>
            {/* Look label */}
            <div style={{
              fontSize: 10,
              fontFamily: "JetBrains Mono, monospace",
              letterSpacing: "0.16em",
              opacity: 0.6,
            }}>
              LOOK N°{lookNum} · {c.mood}
            </div>

            {/* Look name */}
            <h2 style={{
              margin: 0,
              fontFamily: "var(--font-display)",
              fontStyle: "italic",
              fontSize: 64,
              fontWeight: 500,
              letterSpacing: "-0.03em",
              lineHeight: 0.95,
            }}>
              {c.name}
            </h2>

            {/* AI reasoning */}
            <p className="korean-sans" style={{
              margin: 0,
              fontSize: 14,
              lineHeight: 1.7,
              opacity: 0.8,
            }}>
              {c.ai_reasoning}
            </p>

            {/* Palette */}
            <div style={{ display: "flex", gap: 8 }}>
              {c.palette.map((col, ci) => (
                <div
                  key={`${col}-${ci}`}
                  style={{
                    width: 44,
                    height: 44,
                    borderRadius: 2,
                    background: col,
                    border: "1px solid rgba(255,255,255,0.1)",
                    flexShrink: 0,
                  }}
                />
              ))}
            </div>

            {/* Metadata grid */}
            <div style={{
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gap: 0,
              borderTop: isDark ? "1px solid rgba(245,240,230,0.12)" : "1px solid var(--line)",
              paddingTop: 20,
            }}>
              <div>
                <div style={{ fontSize: 9, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.14em", opacity: 0.5, marginBottom: 6 }}>TEMP</div>
                <div style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 500 }}>—</div>
              </div>
              <div>
                <div style={{ fontSize: 9, fontFamily: "JetBrains Mono, monospace", letterSpacing: "0.14em", opacity: 0.5, marginBottom: 6 }}>FIT SCORE</div>
                <div style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 500, color: isDark ? "var(--camel-soft)" : "var(--walnut)" }}>
                  {Number.isFinite(Number(c.fit_score)) ? `${formatFitScore(Number(c.fit_score))}%` : "—"}
                </div>
              </div>
            </div>

            {/* Actions */}
            <div style={{ display: "flex", gap: 10, marginTop: "auto" }}>
              <button
                className={isDark ? "btn btn-camel" : "btn btn-primary"}
                style={{ flex: 1, fontSize: 13, opacity: (!c.id || saving) ? 0.5 : 1 }}
                onClick={() => saveLook(c.id)}
                disabled={!c.id || saving}
              >
                {savedMsg || (saving ? "저장중..." : "저장하기")}
              </button>
              <button style={{
                width: 48,
                height: 48,
                borderRadius: 4,
                border: isDark ? "1px solid rgba(245,240,230,0.2)" : "1px solid var(--line-strong)",
                background: "transparent",
                color: isDark ? "var(--ivory)" : "var(--obsidian)",
                fontSize: 18,
                cursor: "pointer",
                flexShrink: 0,
              }}>
                ♡
              </button>
            </div>
          </div>

          {/* Right col — 2×2 item grid */}
          <div style={{
            background: isDark ? "#2D2A27" : "var(--linen)",
            padding: 24,
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: 12,
            transition: "background 0.35s",
          }}>
            {displayItems.slice(0, 4).map((item, i) => (
              <ItemCard
                key={item.id}
                item={item}
                role={ITEM_ROLES[i] ?? "ACCENT"}
                palette={c.palette}
                isDark={isDark}
                index={i}
              />
            ))}
          </div>
        </div>

        {/* Time-slot carousel */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16, marginTop: 40 }}>
          {TIME_SLOTS.map(slot => (
            <TimeSlotCard key={slot.name} slot={slot} />
          ))}
        </div>
      </section>

      {/* ── 5. AI Reasoning ───────────────────────────────────────── */}
      <section style={{ padding: "80px 48px 80px", maxWidth: 1600, margin: "0 auto" }}>
        <div style={{
          background: "var(--linen)",
          border: "1px solid var(--line)",
          borderRadius: 4,
          padding: 48,
          display: "grid",
          gridTemplateColumns: "1fr 2fr",
          gap: 48,
          alignItems: "flex-start",
        }}>
          {/* Left */}
          <div>
            <div className="eyebrow" style={{ marginBottom: 16 }}>AI REASONING</div>
            <h3 className="korean-serif" style={{
              margin: "0 0 16px",
              fontSize: 36,
              fontWeight: 400,
              letterSpacing: "-0.02em",
              fontFamily: "var(--font-korean-display)",
            }}>
              왜 이 조합일까요?
            </h3>
            <p className="korean-sans" style={{ margin: 0, fontSize: 14, lineHeight: 1.7, color: "var(--text-muted)" }}>
              Claude AI가 TPO 컨텍스트와 옷장 데이터를 분석해 코디를 구성한 이유를 설명합니다.
            </p>
          </div>

          {/* Right — reasoning rows */}
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {reasoningRows.map(row => (
              <div
                key={row.label}
                style={{
                  padding: "16px 20px",
                  background: "rgba(255,255,255,0.6)",
                  borderRadius: 2,
                  display: "grid",
                  gridTemplateColumns: "120px 1fr 60px",
                  gap: 12,
                  alignItems: "center",
                }}
              >
                <div style={{
                  fontSize: 11,
                  fontFamily: "JetBrains Mono, monospace",
                  letterSpacing: "0.08em",
                  color: "var(--text-muted)",
                }}>
                  {row.label}
                </div>
                <div className="korean-sans" style={{ fontSize: 13, color: "var(--obsidian)", lineHeight: 1.5 }}>
                  {row.detail}
                </div>
                <div style={{
                  fontSize: 9,
                  fontFamily: "JetBrains Mono, monospace",
                  letterSpacing: "0.12em",
                  color: "var(--camel)",
                  textAlign: "right",
                  fontWeight: 600,
                }}>
                  {row.tag}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <Footer />
    </main>
  );
}
