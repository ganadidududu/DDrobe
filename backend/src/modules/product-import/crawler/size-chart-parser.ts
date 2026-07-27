import { load } from "cheerio";
import { z } from "zod";
import {
  detectTableUnit,
  normalizeSizeTable
} from "../normalization/product-normalizer";
import type {
  MeasurementUnit,
  NormalizedSizeRow
} from "../product-import.types";

export type ParsedTextSizeTable = {
  readonly rawHeaders: readonly string[];
  readonly rawRows: readonly (readonly string[])[];
  readonly normalizedRows: readonly NormalizedSizeRow[];
  readonly unit: MeasurementUnit;
};

const MEASUREMENT_LABEL =
  "총장|기장|옷길이|어깨(?:너비)?|가슴(?:단면|둘레|파임)?|품|소매(?:길이|기장|통)?|암홀|밑단(?:단면)?|허리(?:단면|둘레)?|엉덩이(?:둘레)?|힙(?:단면|둘레)?|허벅지(?:단면)?|밑위|뒷밑위|인심|안쪽기장|아웃심|발길이|발볼(?:너비)?|굽높이";

const PAIR_PATTERN = new RegExp(
  `(${MEASUREMENT_LABEL})\\s*[:：]?\\s*(-?\\d+(?:\\.\\d+)?(?:\\s*(?:~|〜|–|—)\\s*-?\\d+(?:\\.\\d+)?)?)\\s*(cm|mm|inch|인치)?`,
  "gi"
);
const LABEL_PATTERN = new RegExp(MEASUREMENT_LABEL, "gi");
const STRUCTURED_MEASUREMENT_SCHEMA = z.object({
  sizes: z.array(z.object({
    name: z.string().min(1),
    measure_values: z.array(z.object({
      value: z.union([z.number(), z.string()]),
      spot: z.object({ name: z.string().min(1) })
    }))
  })).min(1)
});
const MUSINSA_MEASUREMENT_SCHEMA = z.object({
  sizes: z.array(z.object({
    name: z.string().min(1),
    items: z.array(z.object({
      name: z.string().min(1),
      value: z.union([z.number(), z.string()])
    }))
  })).min(1)
});

type MeasurementPair = {
  readonly label: string;
  readonly value: string;
  readonly unit: string | null;
  readonly index: number;
};

const clean = (value: string): string => value.replace(/\s+/g, " ").trim();

const linesFromMarkup = (source: string): readonly string[] => {
  if (!/[<>]/.test(source)) return source.split(/\r?\n/).map(clean).filter(Boolean);
  const $ = load(source);
  const lines: string[] = [];
  $("tr,p,li,div").each((_index, element) => {
    const childBlocks = $(element).children("tr,p,li,div").length;
    if (childBlocks > 0) return;
    const innerHtml = $(element).html() ?? "";
    const textWithBreaks = load(innerHtml.replace(/<br\s*\/?>/gi, "\n")).text();
    textWithBreaks.split(/\r?\n/).map(clean).filter(Boolean).forEach((line) => lines.push(line));
  });
  return lines.length > 0 ? lines : [clean($.text())].filter(Boolean);
};

const pairsFromLine = (line: string): readonly MeasurementPair[] => {
  const pairs: MeasurementPair[] = [];
  for (const match of line.matchAll(PAIR_PATTERN)) {
    const label = match[1];
    const value = match[2];
    if (label && value) {
      pairs.push({
        label: clean(label),
        value: clean(value),
        unit: match[3]?.toLowerCase() ?? null,
        index: match.index
      });
    }
  }
  return pairs;
};

const sizeLabelFromPrefix = (prefix: string): string => {
  const cleaned = clean(prefix)
    .replace(/^[•·\-–—*#\s]+/, "")
    .replace(/\b(?:SIZE|사이즈)\b/gi, "")
    .replace(/[:：/\s-]+$/g, "")
    .trim();
  const match = cleaned.match(/(?:^|\s)(FREE|F|XS|S|M|L|XL|XXL|XXXL|\d+(?:\([^)]+\))?)(?:\s*사이즈)?$/i);
  return (match?.[1] ?? "FREE").toUpperCase();
};

const splitCollapsedRows = (line: string): readonly string[] => {
  const rowStart = new RegExp(
    `(?:^|\\s)(?:FREE|XXXL|XXL|XL|XS|S|M|L|F|\\d+(?:\\([^)]+\\)|\\s*사이즈))(?:\\s*사이즈)?\\s*[:：-]?\\s*(?=${MEASUREMENT_LABEL})`,
    "gi"
  );
  const indexes = [...line.matchAll(rowStart)]
    .map((match) => match.index)
    .filter((index): index is number => index !== undefined);
  if (indexes.length < 2) return [line];
  return indexes.map((start, index) => clean(line.slice(start, indexes[index + 1] ?? line.length)));
};

type ParsedRow = {
  readonly sizeLabel: string;
  readonly pairs: readonly MeasurementPair[];
};

const rowsFromLines = (lines: readonly string[]): readonly ParsedRow[] => {
  const rows: ParsedRow[] = [];
  let singletons: MeasurementPair[] = [];
  const flushSingletons = () => {
    if (singletons.length >= 2) rows.push({ sizeLabel: "FREE", pairs: singletons });
    singletons = [];
  };
  for (const line of lines.flatMap(splitCollapsedRows)) {
    const pairs = pairsFromLine(line);
    if (pairs.length >= 2) {
      flushSingletons();
      rows.push({ sizeLabel: sizeLabelFromPrefix(line.slice(0, pairs[0]?.index ?? 0)), pairs });
    } else if (pairs.length === 1 && pairs[0]) {
      const prefix = clean(line.slice(0, pairs[0].index)).replace(/^[•·\-–—*#\s]+/, "");
      if (prefix) flushSingletons();
      else singletons.push(pairs[0]);
    } else {
      flushSingletons();
    }
  }
  flushSingletons();
  const unique = new Map<string, ParsedRow>();
  for (const row of rows) {
    const key = `${row.sizeLabel}:${row.pairs.map((pair) => `${pair.label}=${pair.value}`).join("|")}`;
    unique.set(key, row);
  }
  return [...unique.values()];
};

const buildTable = (rows: readonly ParsedRow[], source: string): ParsedTextSizeTable | null => {
  if (rows.length === 0) return null;
  const headers = ["사이즈", ...new Set(rows.flatMap((row) => row.pairs.map((pair) => pair.label)))];
  const rawRows = rows.map((row) => {
    const values = new Map(row.pairs.map((pair) => [pair.label, pair.value]));
    return [row.sizeLabel, ...headers.slice(1).map((header) => values.get(header) ?? "")];
  });
  const declaredUnit = source.match(/(?:단위|UNIT)\s*[:：]?\s*(cm|mm|inch|인치)/i)?.[1] ?? "";
  const inlineUnits = [...new Set(rows.flatMap((row) => row.pairs.map((pair) => pair.unit).filter(Boolean)))];
  const unit = detectTableUnit([declaredUnit || inlineUnits[0] || ""]);
  return {
    rawHeaders: headers,
    rawRows,
    normalizedRows: normalizeSizeTable(headers, rawRows, unit),
    unit
  };
};

export const decodeHydrationMarkup = (source: string): string => {
  if (!/\\u003c/i.test(source)) return "";
  const $ = load(source);
  return $("script").toArray()
    .map((script) => $(script).text())
    .filter((text) => /\\u003c/i.test(text))
    .join("\n")
    .replace(/\\u003c/gi, "<")
    .replace(/\\u003e/gi, ">")
    .replace(/\\u0026/gi, "&")
    .replace(/\\n/g, "\n");
};

export const parseMeasurementText = (source: string): ParsedTextSizeTable | null => {
  const hydrationMarkup = decodeHydrationMarkup(source);
  if (hydrationMarkup) {
    const hydrationTable = buildTable(rowsFromLines(linesFromMarkup(hydrationMarkup)), hydrationMarkup);
    if (hydrationTable) return hydrationTable;
  }
  return buildTable(rowsFromLines(linesFromMarkup(source)), source);
};

const chartScore = (chart: ParsedTextSizeTable): number =>
  chart.rawRows.length * 10 + chart.rawRows.flat().filter(Boolean).length;

export const extractSizeChartFromUnknown = (root: unknown): ParsedTextSizeTable | null => {
  const queue: unknown[] = [root];
  const charts: ParsedTextSizeTable[] = [];
  let visited = 0;
  while (queue.length > 0 && visited < 10_000) {
    visited += 1;
    const value = queue.shift();
    if (typeof value === "string") {
      const matches = value.match(LABEL_PATTERN);
      if ((matches?.length ?? 0) >= 2) {
        const chart = parseMeasurementText(value);
        if (chart) charts.push(chart);
      }
    } else if (Array.isArray(value)) {
      queue.push(...value);
    } else if (typeof value === "object" && value !== null) {
      const structured = STRUCTURED_MEASUREMENT_SCHEMA.safeParse(value);
      if (structured.success) {
        const headers = [
          "사이즈",
          ...new Set(structured.data.sizes.flatMap((size) =>
            size.measure_values.map((measurement) => measurement.spot.name)))
        ];
        const rawRows = structured.data.sizes.map((size) => {
          const measurements = new Map(size.measure_values.map((measurement) =>
            [measurement.spot.name, String(measurement.value)]));
          return [size.name, ...headers.slice(1).map((header) => measurements.get(header) ?? "")];
        });
        charts.push({
          rawHeaders: headers,
          rawRows,
          normalizedRows: normalizeSizeTable(headers, rawRows, "cm"),
          unit: "cm"
        });
      }
      const musinsa = MUSINSA_MEASUREMENT_SCHEMA.safeParse(value);
      if (musinsa.success) {
        const headers = [
          "사이즈",
          ...new Set(musinsa.data.sizes.flatMap((size) =>
            size.items.map((measurement) => measurement.name)))
        ];
        const rawRows = musinsa.data.sizes.map((size) => {
          const measurements = new Map(size.items.map((measurement) =>
            [measurement.name, String(measurement.value)]));
          return [size.name, ...headers.slice(1).map((header) => measurements.get(header) ?? "")];
        });
        charts.push({
          rawHeaders: headers,
          rawRows,
          normalizedRows: normalizeSizeTable(headers, rawRows, "cm"),
          unit: "cm"
        });
      }
      queue.push(...Object.values(value));
    }
  }
  return charts.sort((left, right) => chartScore(right) - chartScore(left))[0] ?? null;
};

const IMAGE_PATH = /size.*(?:chart|table)|(?:chart|table).*size|measure(?:ment)?.*image|extracted.*measure|사이즈표|실측/i;

export const extractSizeChartImageFromUnknown = (root: unknown): string | null => {
  const queue: Array<{ readonly value: unknown; readonly path: string }> = [{ value: root, path: "" }];
  let visited = 0;
  while (queue.length > 0 && visited < 10_000) {
    visited += 1;
    const current = queue.shift();
    if (!current) break;
    if (typeof current.value === "string" && IMAGE_PATH.test(current.path)) {
      try {
        const url = new URL(current.value);
        if (url.protocol === "http:" || url.protocol === "https:") return url.href;
      } catch (error) {
        if (!(error instanceof TypeError)) throw error;
      }
    } else if (Array.isArray(current.value)) {
      current.value.forEach((value, index) => queue.push({ value, path: `${current.path}.${index}` }));
    } else if (typeof current.value === "object" && current.value !== null) {
      Object.entries(current.value).forEach(([key, value]) => {
        queue.push({ value, path: current.path ? `${current.path}.${key}` : key });
      });
    }
  }
  return null;
};
