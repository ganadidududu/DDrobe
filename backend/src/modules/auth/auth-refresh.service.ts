import { supabaseAuth } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";

export type AuthRefreshResponse = {
  readonly accessToken: string;
  readonly refreshToken: string;
};

type RefreshSessionResult = {
  readonly data: {
    readonly session: {
      readonly access_token?: string;
      readonly refresh_token?: string;
    } | null;
  };
  readonly error: {
    readonly message: string;
    readonly status?: number;
  } | null;
};

export type RefreshSessionAdapter = {
  readonly refreshSession: (input: {
    readonly refresh_token: string;
  }) => Promise<RefreshSessionResult>;
};

const productionRefreshAdapter: RefreshSessionAdapter = {
  refreshSession: async (input) => supabaseAuth.auth.refreshSession(input),
};

export const refreshAuthSession = async (
  refreshToken: string,
  adapter: RefreshSessionAdapter = productionRefreshAdapter
): Promise<AuthRefreshResponse> => {
  const { data, error } = await adapter.refreshSession({ refresh_token: refreshToken });
  if (error) {
    const statusCode = error.status !== undefined && error.status < 500 ? 401 : 503;
    throw createHttpError(statusCode, error.message);
  }
  if (!data.session?.access_token || !data.session.refresh_token) {
    throw createHttpError(401, "Supabase did not return a refreshed session");
  }
  return {
    accessToken: data.session.access_token,
    refreshToken: data.session.refresh_token,
  };
};
