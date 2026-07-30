import assert from "node:assert/strict";
import type { NextFunction, Response } from "express";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AuthenticatedRequest } from "../../shared/types/http";

const prepareFitRecommendation = vi.fn();
const getFitAnalysisResult = vi.fn();
const listRecentFitAnalysisResults = vi.fn();
const replayFitRecommendation = vi.fn();
const findFitAnalysisThreadConsumption = vi.fn();
const createFitAnalysisAndConsumeThread = vi.fn();
const getThreadBalance = vi.fn();

vi.mock("./fit.service", () => ({
  getFitAnalysisResult,
  listRecentFitAnalysisResults,
  prepareFitRecommendation,
  replayFitRecommendation
}));

vi.mock("./reference-profile.service", () => ({
  CLOSET_GARMENT_KINDS: ["upper", "lower"],
  getClosetReferenceProfile: vi.fn()
}));

vi.mock("../thread-wallet/thread-wallet.service", () => ({
  createFitAnalysisAndConsumeThread,
  findFitAnalysisThreadConsumption,
  getThreadBalance
}));

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

const validKey = "11111111-1111-4111-8111-111111111111";

const prepared = {
  response: {
    recommendedSize: "M",
    fitScore: 92,
    fitLabel: "good_fit",
    fitComment: "좋아요",
    recommendationConfidence: "high",
    diff: {},
    partExplanations: [],
    partStatuses: {},
    baseWeights: {},
    dynamicWeights: {},
    referenceVariance: {},
    weightingStrategy: "base_static",
    allSizeScores: [],
    algorithmVersion: "mvp_rule_v1_6"
  },
  persistence: {
    referenceClothingId: "22222222-2222-4222-8222-222222222222",
    externalProductId: "33333333-3333-4333-8333-333333333333",
    recommendedExternalProductSizeId: "44444444-4444-4444-8444-444444444444",
    recommendedSizeLabel: "M",
    fitScore: 92,
    fitLabel: "good_fit",
    fitComment: "좋아요",
    weightedFitDistance: 0.2,
    algorithmVersion: "mvp_rule_v1_6",
    recommendationConfidence: "high",
    resultDetails: {}
  }
};

describe("recommendFitController", () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it("persists and debits through one atomic wallet operation", async () => {
    const { recommendFitController } = await import("./fit.controller");
    findFitAnalysisThreadConsumption.mockResolvedValue(null);
    prepareFitRecommendation.mockResolvedValue(prepared);
    createFitAnalysisAndConsumeThread.mockResolvedValue({
      status: "consumed",
      fitAnalysisResultId: "55555555-5555-4555-8555-555555555555",
      availableThreads: 35
    });
    const response = createResponse();

    await recommendFitController(
      requestWith({
        referenceClothingIds: [prepared.persistence.referenceClothingId],
        externalProductId: prepared.persistence.externalProductId,
        idempotencyKey: validKey
      }),
      response,
      ((error: unknown) => { throw error; }) as NextFunction
    );

    expect(createFitAnalysisAndConsumeThread).toHaveBeenCalledWith(
      "11111111-1111-4111-8111-111111111111",
      validKey,
      prepared.persistence
    );
    assert.equal(response.statusCode, 201);
    assert.deepEqual(response.body, {
      ...prepared.response,
      fitAnalysisResultId: "55555555-5555-4555-8555-555555555555",
      availableThreads: 35
    });
  });

  it("replays a committed request without calculating or charging again", async () => {
    const { recommendFitController } = await import("./fit.controller");
    findFitAnalysisThreadConsumption.mockResolvedValue("55555555-5555-4555-8555-555555555555");
    getThreadBalance.mockResolvedValue(35);
    getFitAnalysisResult.mockResolvedValue({
      id: "55555555-5555-4555-8555-555555555555",
      recommended_size_label: "M",
      fit_score: 92,
      fit_label: "good_fit",
      fit_comment: "좋아요",
      recommendation_confidence: "high",
      algorithm_version: "mvp_rule_v1_6",
      result_details: {
        diffs: {},
        partExplanations: [],
        partStatuses: {},
        baseWeights: {},
        dynamicWeights: {},
        referenceVariance: {},
        weightingStrategy: "base_static",
        allSizeScores: []
      }
    });
    replayFitRecommendation.mockReturnValue({
      ...prepared.response,
      fitAnalysisResultId: "55555555-5555-4555-8555-555555555555"
    });
    const response = createResponse();

    await recommendFitController(
      requestWith({ externalProductId: prepared.persistence.externalProductId, idempotencyKey: validKey }),
      response,
      ((error: unknown) => { throw error; }) as NextFunction
    );

    assert.equal(response.statusCode, 200);
    expect(response.body).toMatchObject({
      fitAnalysisResultId: "55555555-5555-4555-8555-555555555555",
      recommendedSize: "M",
      availableThreads: 35
    });
    expect(prepareFitRecommendation).not.toHaveBeenCalled();
    expect(createFitAnalysisAndConsumeThread).not.toHaveBeenCalled();
    expect(replayFitRecommendation).toHaveBeenCalledOnce();
  });

  it("keeps the unfunded batch route unavailable", async () => {
    const { recommendFitBatchController } = await import("./fit.controller");
    const response = createResponse();

    await recommendFitBatchController(
      requestWith({}),
      response,
      (() => undefined) as NextFunction
    );

    assert.equal(response.statusCode, 410);
  });
});
