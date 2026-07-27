import { load } from "cheerio";
import { env } from "../../../config/env";
import { detectTableUnit, normalizeSizeTable } from "../normalization/product-normalizer";
import type { MeasurementUnit, NormalizedSizeRow } from "../product-import.types";
import { decodeHydrationMarkup, parseMeasurementText } from "./size-chart-parser";

export type ParsedSizeTable = {
  readonly rawHeaders: readonly string[];
  readonly rawRows: readonly (readonly string[])[];
  readonly normalizedRows: readonly NormalizedSizeRow[];
  readonly unit: MeasurementUnit;
};

export type DomProductData = {
  readonly name: string | null;
  readonly brand: string | null;
  readonly category: string | null;
  readonly description: string | null;
  readonly thumbnail: string | null;
  readonly mainImages: readonly string[];
  readonly detailImages: readonly string[];
  readonly sizeChartImage: string | null;
  readonly sizeTable: ParsedSizeTable | null;
};

export type DomExtractionContext = {
  readonly html: string;
  readonly baseUrl: URL;
  readonly includeImages: boolean;
  readonly includeDetailImages: boolean;
};

const cleanText = (value: string): string => value.replace(/\s+/g, " ").trim();

const parseSpan = (value: string | undefined): number => {
  const parsed = Number(value ?? "1");
  return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
};

type TableMatrix = {
  readonly grid: readonly (readonly string[])[];
  readonly headerRowCount: number;
};

const tableMatrix = (html: string): TableMatrix => {
  const $ = load(html);
  const pending = new Map<number, { readonly value: string; remaining: number }>();
  const grid: string[][] = [];
  let headerRowCount = 0;
  let bodyStarted = false;
  $("tr").each((_rowIndex, rowElement) => {
    const hasHeaderCell = $(rowElement).children("th").length > 0;
    const hasDataCell = $(rowElement).children("td").length > 0;
    if (!bodyStarted && hasHeaderCell && !hasDataCell) headerRowCount += 1;
    else bodyStarted = true;
    const row: string[] = [];
    let column = 0;
    const fillPending = () => {
      while (pending.has(column)) {
        const cell = pending.get(column);
        if (!cell) break;
        row[column] = cell.value;
        cell.remaining -= 1;
        if (cell.remaining === 0) pending.delete(column);
        column += 1;
      }
    };
    $(rowElement).children("th,td").each((_cellIndex, cellElement) => {
      fillPending();
      const value = cleanText($(cellElement).text());
      const colspan = parseSpan($(cellElement).attr("colspan"));
      const rowspan = parseSpan($(cellElement).attr("rowspan"));
      for (let offset = 0; offset < colspan; offset += 1) {
        row[column + offset] = value;
        if (rowspan > 1) pending.set(column + offset, { value, remaining: rowspan - 1 });
      }
      column += colspan;
    });
    fillPending();
    if (row.length > 0) grid.push(row.map((cell) => cell ?? ""));
  });
  return { grid, headerRowCount: Math.max(headerRowCount, 1) };
};

export const parseBestSizeTable = (html: string): ParsedSizeTable | null => {
  const $ = load(html);
  const candidates: Array<{ readonly matrix: TableMatrix; readonly score: number }> = [];
  $("table").each((_index, table) => {
    const matrix = tableMatrix($.html(table));
    const { grid } = matrix;
    const text = grid.flat().join(" ");
    const measurementMatches = text.match(/사이즈|실측|총장|어깨|가슴|허리|힙|소매|length|shoulder|chest|waist|size/gi);
    const score = measurementMatches?.length ?? 0;
    if (grid.length >= 2 && grid[0] && grid[0].length >= 2 && score >= 2) candidates.push({ matrix, score });
  });
  const best = candidates.sort((left, right) => right.score - left.score)[0];
  if (!best) return null;
  const headerRows = best.matrix.grid.slice(0, best.matrix.headerRowCount);
  const rows = best.matrix.grid.slice(best.matrix.headerRowCount);
  const width = Math.max(...headerRows.map((row) => row.length));
  const headers = Array.from({ length: width }, (_unused, index) => {
    const labels = headerRows.map((row) => row[index] ?? "").filter(Boolean);
    return labels.at(-1) ?? "";
  });
  const rawRows = rows.map((row) => Array.from({ length: width }, (_unused, index) => row[index] ?? ""));
  const unit = detectTableUnit(best.matrix.grid.flat());
  return { rawHeaders: headers, rawRows, normalizedRows: normalizeSizeTable(headers, rawRows, unit), unit };
};

const resolveImage = (raw: string | undefined, baseUrl: URL): string | null => {
  if (!raw) return null;
  const first = raw.split(",")[0]?.trim().split(/\s+/)[0];
  if (!first) return null;
  try {
    const url = new URL(first, baseUrl);
    return url.protocol === "http:" || url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
};

const imageKey = (url: string): string => {
  const parsed = new URL(url);
  return `${parsed.origin}${parsed.pathname}`;
};

export const extractDomProduct = (context: DomExtractionContext): DomProductData => {
  const { html, baseUrl, includeImages, includeDetailImages } = context;
  const $ = load(html);
  const meta = (property: string): string | null =>
    cleanText($(`meta[property="${property}"], meta[name="${property}"]`).first().attr("content") ?? "") || null;
  const name = meta("og:title")
    ?? (cleanText($("h1, [data-testid*='product-name'], [class*='product-name'], [class*='productName']").first().text())
      || null);
  const brand = cleanText($("[data-testid*='brand'], [class*='brand-name'], [class*='brandName']").first().text()) || null;
  const category = meta("product:category")
    ?? (cleanText($("nav[aria-label*='breadcrumb'], [class*='breadcrumb']").first().text()) || null);
  const description = meta("og:description");
  const thumbnail = includeImages ? resolveImage(meta("og:image") ?? undefined, baseUrl) : null;
  const images = new Map<string, string>();
  let sizeChartImage: string | null = null;
  if (includeImages) {
    $("img").each((_index, image) => {
      const element = $(image);
      const raw = element.attr("src") ?? element.attr("data-src") ?? element.attr("data-original")
        ?? element.attr("data-lazy-src") ?? element.attr("data-image") ?? element.attr("srcset");
      const resolved = resolveImage(raw, baseUrl);
      if (!resolved) return;
      const identity = `${element.attr("alt") ?? ""} ${resolved}`.toLowerCase();
      if (/logo|icon|badge|arrow|payment|profile|avatar|sprite/.test(identity)) return;
      const width = Number(element.attr("width") ?? "0");
      const height = Number(element.attr("height") ?? "0");
      if ((width > 0 && width < 100) || (height > 0 && height < 100)) return;
      if (/size|measurement|사이즈|실측/.test(identity)) sizeChartImage ??= resolved;
      if (images.size < env.maxImages) images.set(imageKey(resolved), resolved);
    });
  }
  const allImages = [...images.values()];
  const mainImages = allImages.slice(0, Math.min(allImages.length, 8));
  const hydrationMarkup = decodeHydrationMarkup(html);
  return {
    name, brand, category, description, thumbnail,
    mainImages,
    detailImages: includeDetailImages ? allImages.slice(mainImages.length) : [],
    sizeChartImage,
    sizeTable: parseBestSizeTable(html)
      ?? (hydrationMarkup ? parseBestSizeTable(hydrationMarkup) : null)
      ?? parseMeasurementText(html)
  };
};
