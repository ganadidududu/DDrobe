import type { AuthResponse } from "./auth.service";

export type GuestUpgradeSession = {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly userId: string;
};

export type GuestIdentityLinkResult =
  | { readonly kind: "linked"; readonly session: AuthResponse }
  | { readonly kind: "identity_exists" };

export type SocialAuthUpgradeDependencies = {
  readonly linkGuestIdentity: (guest: GuestUpgradeSession) => Promise<GuestIdentityLinkResult>;
  readonly signInMember: () => Promise<AuthResponse>;
  readonly mergeGuestData: (guestUserId: string, memberUserId: string) => Promise<void>;
  readonly deleteGuestAuthUser: (guestUserId: string) => Promise<void>;
};

export const authenticateOrUpgradeGuest = async (
  guest: GuestUpgradeSession | null,
  dependencies: SocialAuthUpgradeDependencies
): Promise<AuthResponse> => {
  if (!guest) return dependencies.signInMember();

  const linkResult = await dependencies.linkGuestIdentity(guest);
  switch (linkResult.kind) {
    case "linked":
      return linkResult.session;
    case "identity_exists": {
      const memberSession = await dependencies.signInMember();
      await dependencies.mergeGuestData(guest.userId, memberSession.user.id);
      await dependencies.deleteGuestAuthUser(guest.userId);
      return memberSession;
    }
    default: {
      const exhaustiveResult: never = linkResult;
      return exhaustiveResult;
    }
  }
};
