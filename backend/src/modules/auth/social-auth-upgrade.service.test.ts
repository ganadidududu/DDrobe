import { describe, expect, it } from "vitest";
import type { AuthResponse } from "./auth.service";
import {
  authenticateOrUpgradeGuest,
  type GuestUpgradeSession,
  type SocialAuthUpgradeDependencies,
} from "./social-auth-upgrade.service";

const guest: GuestUpgradeSession = {
  accessToken: "guest-access-token",
  refreshToken: "guest-refresh-token",
  userId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
};

const linkedSession: AuthResponse = {
  accessToken: "linked-access-token",
  refreshToken: "linked-refresh-token",
  user: {
    id: guest.userId,
    email: "linked@example.com",
    isAnonymous: false,
  },
};

const existingMemberSession: AuthResponse = {
  accessToken: "member-access-token",
  refreshToken: "member-refresh-token",
  user: {
    id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    email: "member@example.com",
    isAnonymous: false,
  },
};

describe("guest social identity upgrade", () => {
  it("keeps the guest UUID when linking a new social identity", async () => {
    // Given
    const events: string[] = [];
    const dependencies = createDependencies(events, "linked");

    // When
    const result = await authenticateOrUpgradeGuest(guest, dependencies);

    // Then
    expect(result).toEqual(linkedSession);
    expect(events).toEqual(["link"]);
  });

  it("merges guest data before deleting a guest whose social identity already exists", async () => {
    // Given
    const events: string[] = [];
    const dependencies = createDependencies(events, "identity_exists");

    // When
    const result = await authenticateOrUpgradeGuest(guest, dependencies);

    // Then
    expect(result).toEqual(existingMemberSession);
    expect(events).toEqual(["link", "sign-in", "merge", "delete-guest"]);
  });

  it("preserves the guest auth user when account data migration fails", async () => {
    // Given
    const events: string[] = [];
    const dependencies = createDependencies(events, "identity_exists", true);

    // When / Then
    await expect(authenticateOrUpgradeGuest(guest, dependencies)).rejects.toThrow("merge failed");
    expect(events).toEqual(["link", "sign-in", "merge"]);
  });
});

const createDependencies = (
  events: string[],
  linkResult: "linked" | "identity_exists",
  mergeFails = false
): SocialAuthUpgradeDependencies => ({
  linkGuestIdentity: async () => {
    events.push("link");
    return linkResult === "linked"
      ? { kind: "linked", session: linkedSession }
      : { kind: "identity_exists" };
  },
  signInMember: async () => {
    events.push("sign-in");
    return existingMemberSession;
  },
  mergeGuestData: async () => {
    events.push("merge");
    if (mergeFails) throw new Error("merge failed");
  },
  deleteGuestAuthUser: async () => {
    events.push("delete-guest");
  },
});
