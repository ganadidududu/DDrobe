"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { AccountShell } from "../../../components/AccountShell";
import { clearStoredAuthNextPath, getStoredAuthNextPath, useAuth } from "../../../lib/auth-context";
import { supabaseBrowser } from "../../../lib/supabase-auth";

function AuthCallbackPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { isAuthenticated, isLoading, onboardingComplete } = useAuth();
  const [error, setError] = useState("");

  useEffect(() => {
    const completeAuthentication = async (): Promise<void> => {
      if (!supabaseBrowser) {
        setError("소셜 로그인 설정을 찾지 못했어요. 로그인 화면에서 다시 시도해 주세요.");
        return;
      }
      const code = searchParams.get("code");
      if (!code) return;
      const { error: exchangeError } = await supabaseBrowser.auth.exchangeCodeForSession(code);
      if (exchangeError) setError(exchangeError.message);
    };
    void completeAuthentication();
  }, [searchParams]);

  useEffect(() => {
    if (isLoading || !isAuthenticated || error) return;
    const nextPath = getStoredAuthNextPath();
    clearStoredAuthNextPath();
    router.replace(onboardingComplete ? nextPath : "/onboarding");
  }, [error, isAuthenticated, isLoading, onboardingComplete, router]);

  return (
    <AccountShell
      eyebrow="SECURE ACCOUNT HANDOFF"
      title={<>당신의 계정을<br /><em>확인하고 있어요.</em></>}
      summary="잠시만 기다려 주세요. 인증이 끝나면 다음 단계로 안전하게 이동합니다."
    >
      <div className="account-status-card" aria-live="polite">
        <div className="account-status-card__spinner" aria-hidden="true" />
        <h2>{error ? "로그인을 완료하지 못했어요" : "로그인 확인 중"}</h2>
        <p>{error || "암호를 저장하지 않는 소셜 로그인으로 계정을 확인하고 있어요."}</p>
        {error ? <button className="btn btn-primary" onClick={() => router.replace("/login")}>로그인으로 돌아가기</button> : null}
      </div>
    </AccountShell>
  );
}

export default function AuthCallbackPage() {
  return <Suspense fallback={<main className="auth-gate">로그인 확인을 준비하고 있어요.</main>}><AuthCallbackPageContent /></Suspense>;
}
