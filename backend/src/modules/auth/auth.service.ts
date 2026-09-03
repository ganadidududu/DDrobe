import {
  createSupabaseAuthClient,
  supabase,
  supabaseAdmin,
  supabaseAuth,
} from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import { upsertUserProfile } from "../users/users.service";
import {
  authenticateOrUpgradeGuest,
  type GuestUpgradeSession,
  type GuestIdentityLinkResult,
} from "./social-auth-upgrade.service";

export interface AuthResponse {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly user: {
    readonly id: string;
    readonly email: string;
    readonly isAnonymous: boolean;
  };
}

const toAuthResponse = async (
  authUser: { readonly id: string; readonly email?: string },
  session: { readonly access_token?: string; readonly refresh_token?: string } | null
): Promise<AuthResponse> => {
  if (!authUser.email) throw createHttpError(400, "Auth user email is missing");
  if (!session?.access_token || !session.refresh_token) {
    throw createHttpError(401, "Supabase did not return an active session");
  }

  await upsertUserProfile({ id: authUser.id, email: authUser.email });

  return {
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    user: { id: authUser.id, email: authUser.email, isAnonymous: false }
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
  guest: GuestUpgradeSession | null = null
): Promise<AuthResponse> => loginWithSocialIdToken({ provider: "google", idToken }, guest);

export const loginWithAppleIdToken = async (
  idToken: string,
  nonce: string,
  guest: GuestUpgradeSession | null = null
): Promise<AuthResponse> => {
  return loginWithSocialIdToken({ provider: "apple", idToken, nonce }, guest);
};

type SocialIdToken =
  | { readonly provider: "google"; readonly idToken: string }
  | { readonly provider: "apple"; readonly idToken: string; readonly nonce: string };

const socialCredentials = (credential: SocialIdToken) => {
  switch (credential.provider) {
    case "google":
      return { provider: "google", token: credential.idToken } as const;
    case "apple":
      return {
        provider: "apple",
        token: credential.idToken,
        nonce: credential.nonce,
      } as const;
    default: {
      const exhaustiveCredential: never = credential;
      return exhaustiveCredential;
    }
  }
};

const signInMember = async (credential: SocialIdToken): Promise<AuthResponse> => {
  const { data, error } = await supabaseAuth.auth.signInWithIdToken(socialCredentials(credential));
  if (error || !data.user) {
    throw createHttpError(401, error?.message ?? `${credential.provider} login failed`);
  }
  return toAuthResponse(data.user, data.session);
};

const linkGuestIdentity = async (
  credential: SocialIdToken,
  guest: GuestUpgradeSession
): Promise<GuestIdentityLinkResult> => {
  const guestAuth = createSupabaseAuthClient();
  const { data: guestData, error: guestError } = await guestAuth.auth.setSession({
    access_token: guest.accessToken,
    refresh_token: guest.refreshToken,
  });
  if (
    guestError
    || !guestData.user
    || guestData.user.id !== guest.userId
    || guestData.user.is_anonymous !== true
  ) {
    throw createHttpError(401, guestError?.message ?? "Guest session is invalid");
  }

  const { data, error } = credential.provider === "google"
    ? await guestAuth.auth.linkIdentity({ provider: "google", token: credential.idToken })
    : await guestAuth.auth.linkIdentity({
        provider: "apple",
        token: credential.idToken,
        nonce: credential.nonce,
      });
  if (error?.code === "identity_already_exists") return { kind: "identity_exists" };
  if (error || !data.user) {
    throw createHttpError(401, error?.message ?? "Social identity could not be linked");
  }
  return { kind: "linked", session: await toAuthResponse(data.user, data.session) };
};

const loginWithSocialIdToken = async (
  credential: SocialIdToken,
  guest: GuestUpgradeSession | null
): Promise<AuthResponse> => authenticateOrUpgradeGuest(guest, {
  linkGuestIdentity: async (activeGuest) => linkGuestIdentity(credential, activeGuest),
  signInMember: async () => signInMember(credential),
  mergeGuestData: async (guestUserId, memberUserId) => {
    const { error } = await supabase.rpc("merge_guest_account", {
      p_guest_user_id: guestUserId,
      p_member_user_id: memberUserId,
    });
    if (error) throw createHttpError(500, error.message);
  },
  deleteGuestAuthUser: async (guestUserId) => {
    try {
      const { error } = await supabaseAdmin.auth.admin.deleteUser(guestUserId);
      if (error) {
        console.warn("Guest auth cleanup failed after account merge", {
          guestUserId,
          reason: error.message,
        });
      }
    } catch (error) {
      console.warn("Guest auth cleanup failed after account merge", {
        guestUserId,
        reason: error instanceof Error ? error.message : "Unknown cleanup failure",
      });
    }
  },
});
