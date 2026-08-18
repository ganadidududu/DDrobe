import assert from "node:assert/strict";
import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import type { CompleteOnboardingResult, OnboardingAuthUser } from "./auth-onboarding.types";

process.env.SUPABASE_URL = process.env.SUPABASE_URL ?? "http://localhost:54321";
process.env.SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ?? "anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "service-role-key";

type CapturedResponse = {
  statusCode: number | null;
  body: unknown;
};

type ResponseDouble = Pick<Response, "status" | "json"> & CapturedResponse;

const result: CompleteOnboardingResult = {
  onboardingComplete: true,
  bodyMeasurementsSaved: true,
  user: {
    id: "user-1", email: "user@example.com",
    display_name: "Mina",
    gender: null,
    birth_date: null,
    birth_year: null,
    created_at: "2026-07-08T00:00:00.000Z", updated_at: "2026-07-08T00:00:00.000Z"
  },
  consentRows: [
    {
      id: "consent-1", user_id: "user-1", consent_key: "terms_of_service", consent_version: "2026-07-07",
      accepted: true,
      accepted_at: "2026-07-08T00:00:00.000Z",
      revoked_at: null,
      required: true,
      ip_address: "127.0.0.1", user_agent: "agent",
      created_at: "2026-07-08T00:00:00.000Z", updated_at: "2026-07-08T00:00:00.000Z"
    },
    {
      id: "consent-2", user_id: "user-1", consent_key: "privacy_policy", consent_version: "2026-07-07",
      accepted: true,
      accepted_at: "2026-07-08T00:00:00.000Z",
      revoked_at: null,
      required: true,
      ip_address: "127.0.0.1", user_agent: "agent",
      created_at: "2026-07-08T00:00:00.000Z", updated_at: "2026-07-08T00:00:00.000Z"
    }
  ]
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

const createRequest = (authorization?: string): AuthenticatedRequest => {
  return {
    headers: {
      authorization,
      "user-agent": "agent"
    },
    body: { displayName: "Mina" },
    ip: "127.0.0.1",
    user: { id: "local-user", email: "local@example.com" }
  } as AuthenticatedRequest;
};

let routeStack: readonly { readonly name?: string }[] = [];

const assertNextErrorStatus = (error: unknown, statusCode: number): void => {
  assert.ok(error instanceof Error);
  assert.equal("statusCode" in error ? error.statusCode : undefined, statusCode);
};

type CompleteOnboardingHandlerDependencies = {
  readonly verifySupabaseBearer: (token: string) => Promise<OnboardingAuthUser | null>;
  readonly completeOnboarding: (
    authUser: OnboardingAuthUser,
    payload: unknown,
    options: { readonly ipAddress?: string | null; readonly userAgent?: string | null }
  ) => Promise<CompleteOnboardingResult>;
};

type CompleteOnboardingController = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => Promise<void>;

type CompleteOnboardingControllerModule = {
  readonly createCompleteOnboardingController: (
    dependencies: CompleteOnboardingHandlerDependencies
  ) => CompleteOnboardingController;
};

const loadCreateController = async () => {
  const module: CompleteOnboardingControllerModule = await import("./auth-onboarding.controller");
  return module.createCompleteOnboardingController;
};

const isOnboardingRouteLayer = (layer: unknown): boolean => {
  if (!layer || typeof layer !== "object" || !("route" in layer)) return false;
  const route = layer.route;
  if (!route || typeof route !== "object") return false;
  if (!("path" in route) || route.path !== "/auth/onboarding") return false;
  if (!("methods" in route) || !route.methods || typeof route.methods !== "object") return false;
  return "post" in route.methods && route.methods.post === true;
};

const tests: readonly {
  readonly name: string;
  readonly run: () => Promise<void> | void;
}[] = [
  {
    name: "route is mounted as POST /auth/onboarding after auth middleware",
    run: () => {
      const authIndex = routeStack.findIndex((layer) => layer.name === "authMiddleware"), routeIndex = routeStack.findIndex(isOnboardingRouteLayer);
      assert.ok(authIndex >= 0);
      assert.ok(routeIndex > authIndex);
    }
  },
  {
    name: "missing bearer returns 401 before service",
    run: async () => {
      let serviceCalled = false;
      const createController = await loadCreateController();
      const controller = createController({
        verifySupabaseBearer: async () => ({ id: "user-1", email: "user@example.com" }),
        completeOnboarding: async () => {
          serviceCalled = true;
          return result;
        }
      });
      const response = createResponse();
      let nextError: unknown;
      await controller(createRequest(), response, ((error: unknown) => {
        nextError = error;
      }) as NextFunction);
      assert.equal(serviceCalled, false);
      assertNextErrorStatus(nextError, 401);
    }
  },
  {
    name: "local JWT fallback bearer returns 401 before service",
    run: async () => {
      let verifiedToken: string | null = null;
      let serviceCalled = false;
      const createController = await loadCreateController();
      const controller = createController({
        verifySupabaseBearer: async (token) => {
          verifiedToken = token;
          return null;
        },
        completeOnboarding: async () => {
          serviceCalled = true;
          return result;
        }
      });
      const response = createResponse();
      let nextError: unknown;
      await controller(createRequest("Bearer local.jwt.token"), response, ((error: unknown) => {
        nextError = error;
      }) as NextFunction);
      assert.equal(verifiedToken, "local.jwt.token");
      assert.equal(serviceCalled, false);
      assertNextErrorStatus(nextError, 401);
    }
  },
  {
    name: "Supabase-valid bearer calls service and returns 200 onboarding shape",
    run: async () => {
      let serviceUserId: string | null = null;
      const createController = await loadCreateController();
      const controller = createController({
        verifySupabaseBearer: async () => ({ id: "user-1", email: "user@example.com" }),
        completeOnboarding: async (authUser) => {
          serviceUserId = authUser.id;
          return result;
        }
      });
      const response = createResponse();
      await controller(createRequest("Bearer supabase-token"), response, ((error: unknown) => {
        throw error;
      }) as NextFunction);
      assert.equal(serviceUserId, "user-1");
      assert.equal(response.statusCode, 200);
      assert.deepEqual(response.body, {
        onboardingComplete: true,
        user: {
          id: "user-1", email: "user@example.com",
          display_name: "Mina",
          gender: null,
          birth_date: null,
          birth_year: null,
          created_at: "2026-07-08T00:00:00.000Z", updated_at: "2026-07-08T00:00:00.000Z"
        },
        consentStatus: {
          savedConsentKeys: ["terms_of_service", "privacy_policy"],
          requiredAccepted: true,
          optionalAccepted: []
        },
        bodyMeasurementsSaved: true
      });
    }
  },
  {
    name: "missing displayName is rejected through service",
    run: async () => {
      const createController = await loadCreateController();
      const controller = createController({
        verifySupabaseBearer: async () => ({ id: "user-1", email: "user@example.com" }),
        completeOnboarding: async () => {
          const error = new Error("displayName is required");
          Object.assign(error, { statusCode: 400 });
          throw error;
        }
      });
      const request = createRequest("Bearer supabase-token");
      request.body = {};
      const response = createResponse();
      let nextError: unknown;
      await controller(request, response, ((error: unknown) => {
        nextError = error;
      }) as NextFunction);
      assertNextErrorStatus(nextError, 400);
    }
  }
];

const runTests = async (): Promise<void> => {
  const { routes } = await import("../../routes");
  routeStack = routes.stack;
  for (const test of tests) {
    await test.run();
    console.log(`PASS ${test.name}`);
  }
};

runTests().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
