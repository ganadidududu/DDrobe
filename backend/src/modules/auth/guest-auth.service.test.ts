import { describe, expect, it } from "vitest";
import type { AuthResponse } from "./auth.service";
import {
  claimGuestWelcome,
  createGuestSession,
  type DeviceWelcomeRegistry,
  type GuestClaimState,
  type GuestSessionRepository,
  type GuestWelcomeRepository,
} from "./guest-auth.service";

const guestSession: AuthResponse = {
  accessToken: "guest-access-token",
  refreshToken: "guest-refresh-token",
  user: {
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    email: "guest+aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa@guest.coordit.invalid",
    isAnonymous: true,
  },
};

describe("guest authentication", () => {
  it("creates a server-backed anonymous session before welcome redemption", async () => {
    // Given
    const mutableProfiles: { userId: string; email: string }[] = [];
    const repository: GuestSessionRepository = {
      createAnonymousSession: async () => guestSession,
      createGuestProfile: async (userId, placeholderEmail) => {
        mutableProfiles.push({ userId, email: placeholderEmail });
      },
    };

    // When
    const created = await createGuestSession(repository);

    // Then
    expect(created).toEqual(guestSession);
    expect(mutableProfiles).toEqual([
      {
        userId: guestSession.user.id,
        email: guestSession.user.email,
      },
    ]);
  });

  it("grants exactly three threads when a device has not redeemed the welcome offer", async () => {
    // Given
    const events: string[] = [];
    const repository = welcomeRepository("pending", events, 3);
    const registry = deviceRegistry(false, events);

    // When
    const result = await claimGuestWelcome(
      guestSession.user.id,
      "device-token",
      { repository, deviceRegistry: registry }
    );

    // Then
    expect(result).toEqual({ availableThreads: 3, status: "granted" });
    expect(events).toEqual(["prepare", "device-query", "eligible", "device-mark", "complete"]);
  });

  it("does not grant more threads when the device already redeemed the offer", async () => {
    // Given
    const events: string[] = [];
    const repository = welcomeRepository("pending", events, 0);
    const registry = deviceRegistry(true, events);

    // When
    const result = await claimGuestWelcome(
      guestSession.user.id,
      "device-token",
      { repository, deviceRegistry: registry }
    );

    // Then
    expect(result).toEqual({ availableThreads: 0, status: "already_claimed" });
    expect(events).toEqual(["prepare", "device-query", "deny"]);
  });

  it("completes an eligible claim after a retry without querying eligibility again", async () => {
    // Given
    const events: string[] = [];
    const repository = welcomeRepository("eligible", events, 3);
    const registry = deviceRegistry(true, events);

    // When
    const result = await claimGuestWelcome(
      guestSession.user.id,
      "device-token",
      { repository, deviceRegistry: registry }
    );

    // Then
    expect(result).toEqual({ availableThreads: 3, status: "granted" });
    expect(events).toEqual(["prepare", "device-mark", "complete"]);
  });
});

const welcomeRepository = (
  initialState: GuestClaimState,
  events: string[],
  balance: number
): GuestWelcomeRepository => ({
  prepareClaim: async () => {
    events.push("prepare");
    return initialState;
  },
  markEligible: async () => {
    events.push("eligible");
  },
  completeClaim: async () => {
    events.push("complete");
    return balance;
  },
  denyClaim: async () => {
    events.push("deny");
    return balance;
  },
});

const deviceRegistry = (
  claimed: boolean,
  events: string[]
): DeviceWelcomeRegistry => ({
  hasClaimedWelcome: async () => {
    events.push("device-query");
    return claimed;
  },
  markWelcomeClaimed: async () => {
    events.push("device-mark");
  },
});
