"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect } from "react";
import { useAuth } from "../lib/auth-context";

const PUBLIC_PATHS = new Set(["/", "/login", "/auth/callback", "/terms", "/privacy"]);

type AuthRouteGuardProps = {
  readonly children: React.ReactNode;
};

export function AuthRouteGuard({ children }: AuthRouteGuardProps) {
  const pathname = usePathname();
  const router = useRouter();
  const { isAuthenticated, isLoading, onboardingComplete } = useAuth();
  const isPublic = PUBLIC_PATHS.has(pathname);
  const isOnboarding = pathname === "/onboarding";

  useEffect(() => {
    if (isPublic || isLoading) return;
    if (!isAuthenticated) {
      router.replace(`/login?next=${encodeURIComponent(pathname)}`);
      return;
    }
    if (!isOnboarding && onboardingComplete === false) {
      router.replace(`/onboarding?next=${encodeURIComponent(pathname)}`);
    }
  }, [isAuthenticated, isLoading, isOnboarding, isPublic, onboardingComplete, pathname, router]);

  if (isPublic) return <>{children}</>;

  if (isLoading || !isAuthenticated || (!isOnboarding && onboardingComplete !== true)) {
    return (
      <main className="auth-gate" aria-live="polite">
        <div className="auth-gate__line" />
        <p>나만의 옷장을 확인하고 있어요.</p>
      </main>
    );
  }

  return <>{children}</>;
}
