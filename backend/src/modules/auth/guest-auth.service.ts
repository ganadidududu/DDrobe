import type { AuthResponse } from "./auth.service";

export const guestClaimStates = ["pending", "eligible", "granted", "denied"] as const;
export type GuestClaimState = (typeof guestClaimStates)[number];

export interface GuestSessionRepository {
  readonly createAnonymousSession: () => Promise<AuthResponse>;
  readonly createGuestProfile: (userId: string, placeholderEmail: string) => Promise<void>;
}

export interface GuestWelcomeRepository {
  readonly prepareClaim: (userId: string) => Promise<GuestClaimState>;
  readonly markEligible: (userId: string) => Promise<void>;
  readonly completeClaim: (userId: string) => Promise<number>;
  readonly denyClaim: (userId: string) => Promise<number>;
}

export interface DeviceWelcomeRegistry {
  readonly hasClaimedWelcome: (deviceToken: string) => Promise<boolean>;
  readonly markWelcomeClaimed: (deviceToken: string) => Promise<void>;
}

export type GuestWelcomeResult = {
  readonly availableThreads: number;
  readonly status: "already_claimed" | "granted";
};

export type GuestWelcomeDependencies = {
  readonly repository: GuestWelcomeRepository;
  readonly deviceRegistry: DeviceWelcomeRegistry;
};

export const createGuestSession = async (
  repository: GuestSessionRepository
): Promise<AuthResponse> => {
  const session = await repository.createAnonymousSession();
  await repository.createGuestProfile(session.user.id, session.user.email);
  return session;
};

export const claimGuestWelcome = async (
  userId: string,
  deviceToken: string,
  dependencies: GuestWelcomeDependencies
): Promise<GuestWelcomeResult> => {
  const claimState = await dependencies.repository.prepareClaim(userId);
  switch (claimState) {
    case "pending": {
      const claimed = await dependencies.deviceRegistry.hasClaimedWelcome(deviceToken);
      if (claimed) {
        return {
          availableThreads: await dependencies.repository.denyClaim(userId),
          status: "already_claimed",
        };
      }
      await dependencies.repository.markEligible(userId);
      await dependencies.deviceRegistry.markWelcomeClaimed(deviceToken);
      return {
        availableThreads: await dependencies.repository.completeClaim(userId),
        status: "granted",
      };
    }
    case "eligible":
      await dependencies.deviceRegistry.markWelcomeClaimed(deviceToken);
      return {
        availableThreads: await dependencies.repository.completeClaim(userId),
        status: "granted",
      };
    case "granted":
      return {
        availableThreads: await dependencies.repository.completeClaim(userId),
        status: "already_claimed",
      };
    case "denied":
      return {
        availableThreads: await dependencies.repository.denyClaim(userId),
        status: "already_claimed",
      };
    default: {
      const exhaustiveClaimState: never = claimState;
      return exhaustiveClaimState;
    }
  }
};
