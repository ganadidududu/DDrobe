import type {
  MeasurementType,
  MeasurementUnit,
  NormalizedCategory,
  NormalizedMeasurementValue,
  NormalizedSizeRow
} from "../product-import.types";

type MeasurementAlias = {
  readonly key: string;
  readonly type: MeasurementType;
};

const compact = (value: string): string =>
  value.trim().toUpperCase()
    .replace(/[\s_()（）[\]:：/-]+/g, "")
    .replace(/CM|MM|INCH|인치/g, "");

const ALIASES: Readonly<Record<string, MeasurementAlias>> = {
  총장: { key: "totalLength", type: "length" },
  총길이: { key: "totalLength", type: "length" },
  기장: { key: "totalLength", type: "length" },
  전체길이: { key: "totalLength", type: "length" },
  옷길이: { key: "totalLength", type: "length" },
  LENGTH: { key: "totalLength", type: "length" },
  어깨: { key: "shoulderWidth", type: "width" },
  어깨단면: { key: "shoulderWidth", type: "width" },
  어깨너비: { key: "shoulderWidth", type: "width" },
  SHOULDER: { key: "shoulderWidth", type: "width" },
  가슴단면: { key: "chestWidth", type: "width" },
  가슴너비: { key: "chestWidth", type: "width" },
  가슴: { key: "chestWidth", type: "width" },
  품: { key: "chestWidth", type: "width" },
  CHESTWIDTH: { key: "chestWidth", type: "width" },
  가슴둘레: { key: "chestCircumference", type: "circumference" },
  CHESTCIRCUMFERENCE: { key: "chestCircumference", type: "circumference" },
  소매: { key: "sleeveLength", type: "length" },
  소매길이: { key: "sleeveLength", type: "length" },
  SLEEVE: { key: "sleeveLength", type: "length" },
  암홀: { key: "armhole", type: "length" },
  ARMHOLE: { key: "armhole", type: "length" },
  밑단단면: { key: "hemWidth", type: "width" },
  HEM: { key: "hemWidth", type: "width" },
  허리: { key: "waistWidth", type: "width" },
  허리너비: { key: "waistWidth", type: "width" },
  허리단면: { key: "waistWidth", type: "width" },
  WAISTWIDTH: { key: "waistWidth", type: "width" },
  허리둘레: { key: "waistCircumference", type: "circumference" },
  WAISTCIRCUMFERENCE: { key: "waistCircumference", type: "circumference" },
  엉덩이: { key: "hipWidth", type: "width" },
  엉덩이너비: { key: "hipWidth", type: "width" },
  힙: { key: "hipWidth", type: "width" },
  HIPWIDTH: { key: "hipWidth", type: "width" },
  엉덩이둘레: { key: "hipCircumference", type: "circumference" },
  HIPCIRCUMFERENCE: { key: "hipCircumference", type: "circumference" },
  허벅지: { key: "thighWidth", type: "width" },
  허벅지너비: { key: "thighWidth", type: "width" },
  허벅지단면: { key: "thighWidth", type: "width" },
  THIGH: { key: "thighWidth", type: "width" },
  밑위: { key: "frontRise", type: "length" },
  밑위너비: { key: "frontRise", type: "length" },
  RISE: { key: "frontRise", type: "length" },
  FRONTRISE: { key: "frontRise", type: "length" },
  뒷밑위: { key: "backRise", type: "length" },
  BACKRISE: { key: "backRise", type: "length" },
  LEGOPENING: { key: "legOpening", type: "width" },
  밑단: { key: "legOpening", type: "width" },
  밑단너비: { key: "legOpening", type: "width" },
  아웃심: { key: "outseam", type: "length" },
  OUTSEAM: { key: "outseam", type: "length" },
  인심: { key: "inseam", type: "length" },
  안쪽기장: { key: "inseam", type: "length" },
  INSEAM: { key: "inseam", type: "length" },
  발길이: { key: "footLength", type: "length" },
  FOOTLENGTH: { key: "footLength", type: "length" },
  발볼: { key: "footWidth", type: "width" },
  발볼너비: { key: "footWidth", type: "width" },
  FOOTWIDTH: { key: "footWidth", type: "width" },
  굽높이: { key: "heelHeight", type: "length" },
  HEELHEIGHT: { key: "heelHeight", type: "length" },
  머리둘레: { key: "headCircumference", type: "circumference" },
  모자둘레: { key: "headCircumference", type: "circumference" },
  HEADCIRCUMFERENCE: { key: "headCircumference", type: "circumference" },
  챙길이: { key: "brimLength", type: "length" },
  BRIMLENGTH: { key: "brimLength", type: "length" },
  모자높이: { key: "crownHeight", type: "length" },
  CROWNHEIGHT: { key: "crownHeight", type: "length" }
};

const detectUnit = (value: string): MeasurementUnit => {
  const normalized = value.toLowerCase();
  if (normalized.includes("inch") || normalized.includes("인치") || normalized.includes("\"")) return "inch";
  if (normalized.includes("mm")) return "mm";
  if (normalized.includes("cm") || normalized.includes("센티")) return "cm";
  return "unknown";
};

export const detectTableUnit = (headers: readonly string[], htmlText = ""): MeasurementUnit => {
  const unit = detectUnit([...headers, htmlText].join(" "));
  return unit;
};

export const normalizeMeasurement = (
  rawValue: string,
  rawUnit: MeasurementUnit,
  measurementType: MeasurementType
): NormalizedMeasurementValue => {
  const trimmed = rawValue.trim();
  const range = trimmed.match(/(-?\d+(?:\.\d+)?)\s*(?:~|〜|–|—)\s*(-?\d+(?:\.\d+)?)/);
  if (range) {
    return {
      rawValue: trimmed,
      rawUnit,
      normalizedValue: null,
      normalizedUnit: rawUnit === "unknown" ? "unknown" : "cm",
      converted: false,
      measurementType: "range",
      confidence: 0.7,
      warning: "범위 값은 Fit Score 입력에서 제외됩니다."
    };
  }
  const numericText = trimmed.replace(/,/g, "").match(/-?\d+(?:\.\d+)?/);
  const numeric = numericText ? Number(numericText[0]) : null;
  if (numeric === null || !Number.isFinite(numeric)) {
    return {
      rawValue: trimmed || null, rawUnit, normalizedValue: null,
      normalizedUnit: rawUnit, converted: false, measurementType, confidence: 0.2
    };
  }
  if (rawUnit === "inch") {
    return {
      rawValue: trimmed, rawUnit, normalizedValue: Math.round(numeric * 254) / 100,
      normalizedUnit: "cm", converted: true, measurementType, confidence: 0.95
    };
  }
  if (rawUnit === "mm") {
    return {
      rawValue: trimmed, rawUnit, normalizedValue: Math.round(numeric / 10 * 100) / 100,
      normalizedUnit: "cm", converted: true, measurementType, confidence: 0.95
    };
  }
  return {
    rawValue: trimmed, rawUnit, normalizedValue: numeric,
    normalizedUnit: rawUnit, converted: false, measurementType,
    confidence: rawUnit === "unknown" ? 0.5 : 0.95,
    ...(rawUnit === "unknown" ? { warning: "단위를 확인할 수 없습니다." } : {})
  };
};

export const normalizeSizeTable = (
  rawHeaders: readonly string[],
  rawRows: readonly (readonly string[])[],
  unit: MeasurementUnit
): readonly NormalizedSizeRow[] => {
  const cornerHeader = compact(rawHeaders[0] ?? "");
  const transposed = (cornerHeader === "" || /^(사이즈|SIZE)$/.test(cornerHeader))
    && rawRows.filter((row) => Boolean(ALIASES[compact(row[0] ?? "")])).length >= 2;
  if (transposed) {
    return rawHeaders.slice(1).map((sizeLabel, columnIndex) => {
      const measurements: Record<string, NormalizedMeasurementValue> = {};
      const unknownMeasurements: Record<string, NormalizedMeasurementValue> = {};
      for (const row of rawRows) {
        const label = row[0] ?? "";
        const value = row[columnIndex + 1] ?? "";
        const alias = ALIASES[compact(label)];
        if (alias) measurements[alias.key] = normalizeMeasurement(value, unit, alias.type);
        else unknownMeasurements[label] = normalizeMeasurement(value, unit, "unknown");
      }
      return { sizeLabel: sizeLabel.trim().toUpperCase(), measurements, unknownMeasurements };
    });
  }
  return rawRows.map((row) => {
  const measurements: Record<string, NormalizedMeasurementValue> = {};
  const unknownMeasurements: Record<string, NormalizedMeasurementValue> = {};
  for (let index = 1; index < rawHeaders.length; index += 1) {
    const header = rawHeaders[index] ?? "";
    const value = row[index] ?? "";
    const alias = ALIASES[compact(header)];
    if (alias) measurements[alias.key] = normalizeMeasurement(value, unit, alias.type);
    else unknownMeasurements[header] = normalizeMeasurement(value, unit, "unknown");
  }
  return {
    sizeLabel: (row[0] ?? "").trim().toUpperCase().replace(/\s+/g, " "),
    measurements,
    unknownMeasurements
  };
  });
};

export const normalizeCategory = (raw: string | null): NormalizedCategory => {
  if (!raw) return "UNKNOWN";
  const value = compact(raw);
  if (/(티셔츠|반소매|TOP|TSHIRT)/.test(value)) return "TOP";
  if (/(셔츠|남방|SHIRT)/.test(value)) return "SHIRT";
  if (/(니트|스웨터|KNIT|SWEATER)/.test(value)) return "KNIT";
  if (/(맨투맨|SWEATSHIRT)/.test(value)) return "SWEATSHIRT";
  if (/(후드|HOODIE)/.test(value)) return "HOODIE";
  if (/(재킷|자켓|JACKET)/.test(value)) return "JACKET";
  if (/(코트|COAT)/.test(value)) return "COAT";
  if (/(청바지|데님|JEANS)/.test(value)) return "JEANS";
  if (/(반바지|SHORTS)/.test(value)) return "SHORTS";
  if (/(팬츠|바지|PANTS)/.test(value)) return "PANTS";
  if (/(스커트|치마|SKIRT)/.test(value)) return "SKIRT";
  if (/(원피스|DRESS)/.test(value)) return "DRESS";
  if (/(신발|슈즈|SHOES|SNEAKER)/.test(value)) return "SHOES";
  if (/(모자|HAT|CAP)/.test(value)) return "HAT";
  if (/(가방|BAG)/.test(value)) return "BAG";
  if (/(아우터|OUTER)/.test(value)) return "OUTER";
  return "UNKNOWN";
};
