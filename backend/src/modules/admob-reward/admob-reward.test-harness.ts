import assert from "node:assert/strict";
import { createSign, generateKeyPairSync, type KeyObject } from "node:crypto";
import type { Server } from "node:http";
import express, { type RequestHandler } from "express";
import { errorMiddleware } from "../../middleware/error.middleware";

const testKeyId = 1_234_567_890;

export const testConfiguration = {
  rewardedAdsEnabled: true,
  adUnitId: "ca-app-pub-1234567890123456/1234567890",
  rewardItem: "실타래",
  rewardAmount: 1,
  validationCustomData: "coordit-admob-ssv-validation-v1"
} as const;

export const testNowMs = 1_777_777_777_000;

export type CallbackValues = {
  readonly adNetwork: string;
  readonly adUnit: string;
  readonly customData: string | null;
  readonly rewardAmount: string;
  readonly rewardItem: string;
  readonly timestamp: string;
  readonly transactionId: string;
  readonly userId: string | null;
};

type VerifierKey = {
  readonly keyId: number;
  readonly pem: string;
};

type ControllerFactory = (dependencies: {
  readonly getVerifierKeys: () => Promise<readonly VerifierKey[]>;
  readonly grantReward: (
    attemptId: string,
    transactionId: string
  ) => Promise<{ readonly status: "granted"; readonly availableThreads: number }>;
  readonly now: () => number;
  readonly configuration: {
    readonly rewardedAdsEnabled: boolean;
    readonly adUnitId: string;
    readonly rewardItem: string;
    readonly rewardAmount: number;
    readonly validationCustomData: string;
  };
  readonly logRejection: (category: string) => void;
}) => RequestHandler;

type SignedRequestInput = {
  readonly requestContent: string;
  readonly contentToSign?: string;
  readonly keyId?: number;
  readonly tailOrder?: "google" | "reversed";
  readonly mutateSignature?: boolean;
};

type TestConfigurationOverrides = {
  readonly adUnitId?: string;
  readonly rewardItem?: string;
  readonly rewardAmount?: number;
  readonly validationCustomData?: string;
};

export type TestHarness = {
  readonly requestSigned: (input: SignedRequestInput) => Promise<Response>;
  readonly requestRawQuery: (rawQuery: string) => Promise<Response>;
  readonly close: () => Promise<void>;
  readonly grantCalls: () => readonly {
    readonly attemptId: string;
    readonly transactionId: string;
  }[];
  readonly rejectionCategories: () => readonly string[];
};

const isControllerFactory = (value: unknown): value is ControllerFactory => {
  return typeof value === "function";
};

export const loadControllerFactory = async (): Promise<ControllerFactory> => {
  const controllerModule = await import("./admob-reward.controller");
  const factoryEntry = Object.entries(controllerModule).find(([name]) => {
    return name === "createReceiveRewardedSSVController";
  });
  const factory: unknown = factoryEntry?.[1];
  if (!isControllerFactory(factory)) {
    throw new Error("Missing injected AdMob SSV controller factory contract");
  }
  return factory;
};

const encodedPair = (name: string, value: string): string => {
  return `${name}=${encodeURIComponent(value)}`;
};

export const createCanonicalSignedContent = (values: CallbackValues): string => {
  const pairs = [
    encodedPair("ad_network", values.adNetwork),
    encodedPair("ad_unit", values.adUnit)
  ];
  if (values.customData !== null) {
    pairs.push(encodedPair("custom_data", values.customData));
  }
  pairs.push(
    encodedPair("reward_amount", values.rewardAmount),
    encodedPair("reward_item", values.rewardItem),
    encodedPair("timestamp", values.timestamp),
    encodedPair("transaction_id", values.transactionId)
  );
  if (values.userId !== null) {
    pairs.push(encodedPair("user_id", values.userId));
  }
  return pairs.join("&");
};

const closeServer = async (server: Server): Promise<void> => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
};

const sign = (privateKey: KeyObject, content: string): string => {
  const signer = createSign("SHA256");
  signer.update(content, "utf8");
  signer.end();
  return signer.sign(privateKey).toString("base64url");
};

const mutatedSignature = (signature: string): string => {
  const replacement = signature.startsWith("A") ? "B" : "A";
  return `${replacement}${signature.slice(1)}`;
};

export const startTestHarness = async (
  factory: ControllerFactory,
  rewardedAdsEnabled = true,
  configurationOverrides: TestConfigurationOverrides = {}
): Promise<TestHarness> => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1"
  });
  const pem = publicKey.export({ format: "pem", type: "spki" }).toString();
  // Mutable test recorder state; observing calls is its sole purpose.
  const grantCallRecords: { attemptId: string; transactionId: string }[] = [];
  const rejectionCategoryRecords: string[] = [];
  const app = express();
  app.get(
    "/webhooks/admob/rewarded",
    factory({
      getVerifierKeys: async () => [{ keyId: testKeyId, pem }],
      grantReward: async (attemptId, transactionId) => {
        grantCallRecords.push({ attemptId, transactionId });
        return { status: "granted", availableThreads: 37 };
      },
      now: () => testNowMs,
      configuration: {
        ...testConfiguration,
        ...configurationOverrides,
        rewardedAdsEnabled
      },
      logRejection: (category) => rejectionCategoryRecords.push(category)
    })
  );
  app.use(errorMiddleware);

  const server = await new Promise<Server>((resolve, reject) => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
    listener.once("error", reject);
  });
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const baseURL = `http://127.0.0.1:${address.port}`;

  const requestRawQuery = async (rawQuery: string): Promise<Response> => {
    return fetch(`${baseURL}/webhooks/admob/rewarded?${rawQuery}`);
  };

  return {
    requestSigned: async (input) => {
      const keyId = input.keyId ?? testKeyId;
      const contentToSign = input.contentToSign ?? input.requestContent;
      const originalSignature = sign(privateKey, contentToSign);
      const signature = input.mutateSignature === true
        ? mutatedSignature(originalSignature)
        : originalSignature;
      const tail = input.tailOrder === "reversed"
        ? `key_id=${keyId}&signature=${signature}`
        : `signature=${signature}&key_id=${keyId}`;
      return requestRawQuery(`${input.requestContent}&${tail}`);
    },
    requestRawQuery,
    close: async () => closeServer(server),
    grantCalls: () => grantCallRecords,
    rejectionCategories: () => rejectionCategoryRecords
  };
};
