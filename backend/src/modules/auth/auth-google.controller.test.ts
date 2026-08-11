import assert from "node:assert/strict";
import type { NextFunction, Request, Response } from "express";
import { createHttpError } from "../../shared/utils/http-error";
import type { AuthResponse } from "./auth.service";

process.env.SUPABASE_URL = process.env.SUPABASE_URL ?? "http://localhost:54321";
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? "anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "service-role-key";

type CapturedResponse = {
  statusCode: number | null;
  body: unknown;
};

type ResponseDouble = Pick<Response, "status" | "json"> & CapturedResponse;

type GoogleAuthControllerDependencies = {
  readonly loginWithGoogleIdToken: (idToken: string, nonce: string) => Promise<AuthResponse>;
};

type GoogleAuthController = (req: Request, res: Response, next: NextFunction) => Promise<void>;

type GoogleAuthControllerModule = {
  readonly createGoogleLoginController: (dependencies: GoogleAuthControllerDependencies) => GoogleAuthController;
};

const authResponse: AuthResponse = {
  accessToken: "access-token",
  refreshToken: "refresh-token",
  user: {
    id: "google-user-1",
    email: "mina@example.com"
  }
};

const createResponse = (): ResponseDouble & Response => {
  const response: ResponseDouble = {
    statusCode: null,
    body: undefined,
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

const createRequest = (body: unknown): Request => {
  return { body } as Request;
};

const assertNextErrorStatus = (error: unknown, statusCode: number): void => {
  assert.ok(error instanceof Error);
  assert.equal("statusCode" in error ? error.statusCode : undefined, statusCode);
};

const loadCreateController = async () => {
  const module: GoogleAuthControllerModule = await import("./auth.controller");
  return module.createGoogleLoginController;
};

const isGoogleLoginRouteLayer = (layer: unknown): boolean => {
  if (!layer || typeof layer !== "object" || !("route" in layer)) return false;
  const route = layer.route;
  if (!route || typeof route !== "object") return false;
  if (!("path" in route) || route.path !== "/auth/google") return false;
  if (!("methods" in route) || !route.methods || typeof route.methods !== "object") return false;
  return "post" in route.methods && route.methods.post === true;
};

const tests: readonly {
  readonly name: string;
  readonly run: () => Promise<void> | void;
}[] = [
  {
    name: "route is mounted as public POST /auth/google before auth middleware",
    run: async () => {
      const { routes } = await import("../../routes");
      const authIndex = routes.stack.findIndex((layer) => layer.name === "authMiddleware");
      const googleIndex = routes.stack.findIndex(isGoogleLoginRouteLayer);
      assert.ok(googleIndex >= 0);
      assert.ok(authIndex > googleIndex);
    }
  },
  {
    name: "idToken and nonce are parsed and exchanged through service",
    run: async () => {
      let receivedToken: string | null = null;
      let receivedNonce: string | null = null;
      const createController = await loadCreateController();
      const controller = createController({
        loginWithGoogleIdToken: async (idToken, nonce) => {
          receivedToken = idToken;
          receivedNonce = nonce;
          return authResponse;
        }
      });
      const response = createResponse();
      await controller(createRequest({ idToken: " google-id-token ", nonce: " raw-google-nonce " }), response, ((error: unknown) => {
        throw error;
      }) as NextFunction);
      assert.equal(receivedToken, "google-id-token");
      assert.equal(receivedNonce, "raw-google-nonce");
      assert.deepEqual(response.body, authResponse);
    }
  },
  {
    name: "missing Google credentials return 400 before service",
    run: async () => {
      let serviceCalled = false;
      const createController = await loadCreateController();
      const controller = createController({
        loginWithGoogleIdToken: async () => {
          serviceCalled = true;
          throw createHttpError(401, "should not be called");
        }
      });
      const response = createResponse();
      let nextError: unknown;
      await controller(createRequest({ idToken: "google-id-token" }), response, ((error: unknown) => {
        nextError = error;
      }) as NextFunction);
      assert.equal(serviceCalled, false);
      assertNextErrorStatus(nextError, 400);
    }
  }
];

const runTests = async (): Promise<void> => {
  for (const test of tests) {
    await test.run();
    console.log(`PASS ${test.name}`);
  }
};

runTests().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
