import assert from "node:assert/strict";
import type { NextFunction, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AuthenticatedRequest } from "../../shared/types/http";

const generateFitReport = vi.fn();

vi.mock("./fit-report.service", () => ({ generateFitReport }));

type ResponseDouble = Pick<Response, "status" | "json"> & {
  statusCode?: number;
  body?: unknown;
};

const createResponse = (): ResponseDouble & Response => {
  const response: ResponseDouble = {
    status(code: number) {
      response.statusCode = code;
      return response as ResponseDouble & Response;
    },
    json(body: unknown) {
      response.body = body;
      return response as ResponseDouble & Response;
    }
  };
  return response as ResponseDouble & Response;
};

const requestWith = (body: Record<string, unknown>): AuthenticatedRequest => ({
  body,
  user: { id: "11111111-1111-4111-8111-111111111111", email: "fit@example.com" }
}) as AuthenticatedRequest;

const reportRequestWith = (body: Record<string, unknown>): AuthenticatedRequest => {
  const request = requestWith(body);
  Object.defineProperty(request, "params", {
    value: { id: "55555555-5555-4555-8555-555555555555" }
  });
  return request;
};

describe("generateFitReportController", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("rejects a report request without an idempotency key", async () => {
    const { generateFitReportController } = await import("./fit-report.controller");
    const response = createResponse();

    await generateFitReportController(
      reportRequestWith({ selectedSizeLabel: "M" }),
      response,
      ((error: unknown) => { throw error; }) as NextFunction
    );

    assert.equal(response.statusCode, 400);
    assert.deepEqual(response.body, { message: "A valid idempotencyKey is required" });
    expect(generateFitReport).not.toHaveBeenCalled();
  });

  it("passes a valid idempotency key through and returns the remaining balance", async () => {
    const { generateFitReportController } = await import("./fit-report.controller");
    generateFitReport.mockResolvedValue({ availableThreads: 34, report: {} });
    const response = createResponse();
    const idempotencyKey = "77777777-7777-4777-8777-777777777777";

    await generateFitReportController(
      reportRequestWith({ idempotencyKey, selectedSizeLabel: "M" }),
      response,
      ((error: unknown) => { throw error; }) as NextFunction
    );

    expect(generateFitReport).toHaveBeenCalledWith(
      "11111111-1111-4111-8111-111111111111",
      "55555555-5555-4555-8555-555555555555",
      { idempotencyKey, selectedSizeLabel: "M", style: undefined, includeDebug: false }
    );
    assert.equal(response.statusCode, 201);
    assert.deepEqual(response.body, { availableThreads: 34, report: {} });
  });
});
