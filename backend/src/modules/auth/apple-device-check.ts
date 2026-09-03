import { randomUUID } from "node:crypto";
import jwt from "jsonwebtoken";
import ky, { HTTPError, type KyInstance } from "ky";
import { z } from "zod";
import { env } from "../../config/env";
import { createHttpError } from "../../shared/utils/http-error";
import type { DeviceWelcomeRegistry } from "./guest-auth.service";

export type DeviceCheckConfiguration = {
  readonly keyId: string | null;
  readonly teamId: string | null;
  readonly privateKey: string | null;
  readonly environment: "development" | "production";
  readonly baseURL?: string;
};

const queryResponseSchema = z.object({ bit0: z.boolean() });
const appleErrorResponseSchema = z.object({
  error: z.enum([
    "Bad Device Token",
    "Bad Bits",
    "Bad Transaction ID",
    "Bad Timestamp",
    "Bad Authorization Token",
    "Forbidden",
  ]),
});

const appleErrorCode = async (response: Response): Promise<string | null> => {
  try {
    const parsed = appleErrorResponseSchema.safeParse(await response.json());
    return parsed.success ? parsed.data.error : null;
  } catch (error) {
    if (error instanceof SyntaxError) return null;
    throw error;
  }
};

const authorizationToken = (configuration: DeviceCheckConfiguration): string => {
  if (!configuration.keyId || !configuration.teamId || !configuration.privateKey) {
    throw createHttpError(503, "DeviceCheck is not configured");
  }
  return jwt.sign({}, configuration.privateKey.replaceAll("\\n", "\n"), {
    algorithm: "ES256",
    issuer: configuration.teamId,
    keyid: configuration.keyId,
    expiresIn: "5m",
  });
};

const endpointBase = (environment: DeviceCheckConfiguration["environment"]): string =>
  environment === "development"
    ? "https://api.development.devicecheck.apple.com"
    : "https://api.devicecheck.apple.com";

export const createAppleDeviceWelcomeRegistry = (
  configuration: DeviceCheckConfiguration,
  http: KyInstance = ky
): DeviceWelcomeRegistry => {
  const request = async (
    operation: "query_two_bits" | "update_two_bits",
    deviceToken: string,
    bit0?: boolean
  ): Promise<unknown> => {
    const json = {
      device_token: deviceToken,
      transaction_id: randomUUID(),
      timestamp: Date.now(),
      ...(bit0 === undefined ? {} : { bit0 }),
    };
    try {
      const response = await http.post(`${configuration.baseURL ?? endpointBase(configuration.environment)}/v1/${operation}`, {
        headers: { Authorization: `Bearer ${authorizationToken(configuration)}` },
        json,
        retry: { limit: 2, methods: ["post"] },
        timeout: 10_000,
      });
      const responseBody = (await response.text()).trim();
      if (operation === "query_two_bits" && responseBody === "Failed to find bit state") {
        return { bit0: false };
      }
      if (responseBody.length === 0) return {};
      try {
        return JSON.parse(responseBody) as unknown;
      } catch {
        throw createHttpError(502, `DeviceCheck ${operation} returned an invalid response`);
      }
    } catch (error) {
      if (!(error instanceof HTTPError)) throw error;
      const errorCode = await appleErrorCode(error.response);
      const detail = errorCode === null ? "" : `: ${errorCode}`;
      throw createHttpError(
        502,
        `DeviceCheck ${operation} failed (${error.response.status})${detail}`
      );
    }
  };

  return {
    hasClaimedWelcome: async (deviceToken): Promise<boolean> => {
      const response = await request("query_two_bits", deviceToken);
      return queryResponseSchema.parse(response).bit0;
    },
    markWelcomeClaimed: async (deviceToken): Promise<void> => {
      await request("update_two_bits", deviceToken, true);
    },
  };
};

export const appleDeviceWelcomeRegistry = createAppleDeviceWelcomeRegistry({
  keyId: env.appleDeviceCheckKeyId,
  teamId: env.appleDeviceCheckTeamId,
  privateKey: env.appleDeviceCheckPrivateKey,
  environment: env.appleDeviceCheckEnvironment,
});
