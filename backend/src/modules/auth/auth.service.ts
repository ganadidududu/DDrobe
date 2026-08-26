import { supabaseAuth } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import { upsertUserProfile } from "../users/users.service";

export interface AuthResponse {
  accessToken: string;
  refreshToken: string;
  user: {
    id: string;
    email: string;
  };
}

const toAuthResponse = async (
  authUser: { id: string; email?: string },
  session: { access_token?: string; refresh_token?: string } | null
): Promise<AuthResponse> => {
  if (!authUser.email) throw createHttpError(400, "Auth user email is missing");
  if (!session?.access_token || !session.refresh_token) {
    throw createHttpError(401, "Supabase did not return an active session");
  }

  await upsertUserProfile({ id: authUser.id, email: authUser.email });

  return {
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    user: { id: authUser.id, email: authUser.email }
  };
};

export const signupWithEmail = async (
  email: string,
  password: string
): Promise<AuthResponse> => {
  const { data, error } = await supabaseAuth.auth.signUp({ email, password });
  if (error || !data.user) throw createHttpError(400, error?.message ?? "Signup failed");
  return toAuthResponse(data.user, data.session);
};

export const loginWithEmail = async (
  email: string,
  password: string
): Promise<AuthResponse> => {
  const { data, error } = await supabaseAuth.auth.signInWithPassword({ email, password });
  if (error || !data.user) throw createHttpError(401, error?.message ?? "Login failed");
  return toAuthResponse(data.user, data.session);
};

export const loginWithGoogleIdToken = async (
  idToken: string,
  nonce: string
): Promise<AuthResponse> => {
  const { data, error } = await supabaseAuth.auth.signInWithIdToken({
    provider: "google",
    token: idToken,
    nonce
  });
  if (error || !data.user) throw createHttpError(401, error?.message ?? "Google login failed");
  return toAuthResponse(data.user, data.session);
};

export const loginWithAppleIdToken = async (
  idToken: string,
  nonce: string
): Promise<AuthResponse> => {
  const { data, error } = await supabaseAuth.auth.signInWithIdToken({
    provider: "apple",
    token: idToken,
    nonce
  });
  if (error || !data.user) throw createHttpError(401, error?.message ?? "Apple login failed");
  return toAuthResponse(data.user, data.session);
};

export const refreshAuthSession = async (refreshToken: string): Promise<AuthResponse> => {
  const { data, error } = await supabaseAuth.auth.refreshSession({
    refresh_token: refreshToken
  });
  if (error || !data.user) {
    throw createHttpError(401, error?.message ?? "Session refresh failed");
  }
  return toAuthResponse(data.user, data.session);
};
