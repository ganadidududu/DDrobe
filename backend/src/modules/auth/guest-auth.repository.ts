import { supabase, supabaseAuth } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import { upsertUserProfile } from "../users/users.service";
import type { AuthResponse } from "./auth.service";
import type {
  GuestClaimState,
  GuestSessionRepository,
  GuestWelcomeRepository,
} from "./guest-auth.service";

type ClaimStateRow = {
  readonly status: GuestClaimState;
};

type ThreadBalanceRow = {
  readonly available_threads: number;
};

const guestEmail = (userId: string): string =>
  `guest+${userId}@guest.coordit.invalid`;

export const guestSessionRepository: GuestSessionRepository = {
  createAnonymousSession: async (): Promise<AuthResponse> => {
    const { data, error } = await supabaseAuth.auth.signInAnonymously();
    if (error || !data.user || !data.session) {
      throw createHttpError(503, error?.message ?? "Guest session could not be created");
    }
    return {
      accessToken: data.session.access_token,
      refreshToken: data.session.refresh_token,
      user: {
        id: data.user.id,
        email: guestEmail(data.user.id),
        isAnonymous: true,
      },
    };
  },
  createGuestProfile: async (userId, placeholderEmail): Promise<void> => {
    await upsertUserProfile({
      id: userId,
      email: placeholderEmail,
      isGuest: true,
    });
  },
};

const singleBalance = async (
  functionName: "complete_guest_welcome_claim" | "deny_guest_welcome_claim",
  userId: string
): Promise<number> => {
  const { data, error } = await supabase
    .rpc(functionName, { p_user_id: userId })
    .single<ThreadBalanceRow>();
  if (error || !data) {
    throw createHttpError(500, error?.message ?? "Guest welcome balance could not be updated");
  }
  return data.available_threads;
};

export const guestWelcomeRepository: GuestWelcomeRepository = {
  prepareClaim: async (userId): Promise<GuestClaimState> => {
    const { data, error } = await supabase
      .rpc("prepare_guest_welcome_claim", { p_user_id: userId })
      .single<ClaimStateRow>();
    if (error || !data) {
      throw createHttpError(500, error?.message ?? "Guest welcome claim could not be prepared");
    }
    return data.status;
  },
  markEligible: async (userId): Promise<void> => {
    const { error } = await supabase.rpc("mark_guest_welcome_eligible", {
      p_user_id: userId,
    });
    if (error) throw createHttpError(500, error.message);
  },
  completeClaim: async (userId): Promise<number> =>
    singleBalance("complete_guest_welcome_claim", userId),
  denyClaim: async (userId): Promise<number> =>
    singleBalance("deny_guest_welcome_claim", userId),
};
