"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { AccountShell } from "../../components/AccountShell";
import { useAuth } from "../../lib/auth-context";

type Provider = "google" | "apple";

function ProviderMark({ provider }: { readonly provider: Provider }) {
  if (provider === "apple") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path d="M16.7 12.8c0-2.2 1.8-3.3 1.9-3.4-1-1.5-2.6-1.7-3.2-1.8-1.4-.1-2.7.8-3.4.8-.7 0-1.8-.8-3-.8-1.5 0-3 .9-3.8 2.3-1.7 2.9-.4 7.1 1.2 9.4.8 1.1 1.7 2.4 2.9 2.4 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.9-2.3.9-1.3 1.3-2.6 1.3-2.7-.1 0-2.8-1.1-2.8-3.9ZM14.5 6.2c.6-.8 1-1.9.9-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.8-1.3Z" fill="currentColor" />
      </svg>
    );
  }

  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M21.6 12.2c0-.8-.1-1.5-.2-2.2H12v4h5.4a4.6 4.6 0 0 1-2 3v2.6h3.2c1.9-1.7 3-4.3 3-7.4Z" fill="#4285F4" />
      <path d="M12 22c2.7 0 5-.9 6.6-2.4L15.4 17c-.9.6-2 .9-3.4.9-2.6 0-4.8-1.8-5.6-4.1H3.1v2.7A10 10 0 0 0 12 22Z" fill="#34A853" />
      <path d="M6.4 13.8a6 6 0 0 1 0-3.7V7.4H3.1a10 10 0 0 0 0 9.1l3.3-2.7Z" fill="#FBBC05" />
      <path d="M12 6.1c1.5 0 2.9.5 3.9 1.5l2.9-2.9A10 10 0 0 0 3.1 7.4l3.3 2.7C7.2 7.9 9.4 6.1 12 6.1Z" fill="#EA4335" />
    </svg>
  );
}

function LoginPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { isAuthenticated, isLoading, isSupabaseAuthConfigured, onboardingComplete, startSocialLogin } = useAuth();
  const [pendingProvider, setPendingProvider] = useState<Provider | null>(null);
  const [error, setError] = useState("");
  const nextPath = searchParams.get("next")?.startsWith("/") ? searchParams.get("next") ?? "/closet" : "/closet";

  useEffect(() => {
    if (isLoading || !isAuthenticated) return;
    router.replace(onboardingComplete ? nextPath : "/onboarding");
  }, [isAuthenticated, isLoading, nextPath, onboardingComplete, router]);

  const handleProvider = async (provider: Provider): Promise<void> => {
    setError("");
    setPendingProvider(provider);
    try {
      await startSocialLogin(provider, nextPath);
    } catch (providerError) {
      if (providerError instanceof Error) setError(providerError.message);
      else setError("로그인을 시작하지 못했어요. 잠시 후 다시 시도해 주세요.");
      setPendingProvider(null);
    }
  };

  return (
    <AccountShell
      eyebrow="WELCOME TO COORDIT"
      title={<>나에게 맞는 옷을,<br /><em>정확하게.</em></>}
      summary="이메일과 비밀번호 없이, 이미 사용하는 계정으로 안전하게 시작하세요. 첫 로그인 뒤에는 나만의 핏 프로필을 가볍게 설정합니다."
    >
      <div className="social-login">
        <div className="social-login__heading">
          <span className="account-shell__eyebrow">SIGN IN OR CREATE ACCOUNT</span>
          <h2>계속하려면 로그인하세요</h2>
          <p>가입과 로그인은 Google 또는 Apple 계정으로만 진행됩니다.</p>
        </div>

        <div className="social-login__providers">
          <button className="social-login__provider" onClick={() => void handleProvider("google")} disabled={pendingProvider !== null || !isSupabaseAuthConfigured}>
            <ProviderMark provider="google" />
            <span>Google로 계속하기</span>
            <span aria-hidden="true">→</span>
          </button>
          <button className="social-login__provider social-login__provider--apple" onClick={() => void handleProvider("apple")} disabled={pendingProvider !== null || !isSupabaseAuthConfigured}>
            <ProviderMark provider="apple" />
            <span>Apple로 계속하기</span>
            <span aria-hidden="true">→</span>
          </button>
        </div>

        {!isSupabaseAuthConfigured ? (
          <p className="account-form__notice account-form__notice--error" role="alert">소셜 로그인 설정이 아직 완료되지 않았어요. 관리자에게 Google·Apple 로그인 설정을 요청해 주세요.</p>
        ) : null}
        {pendingProvider ? <p className="account-form__notice" aria-live="polite">{pendingProvider === "google" ? "Google" : "Apple"} 로그인 페이지로 이동하고 있어요.</p> : null}
        {error ? <p className="account-form__notice account-form__notice--error" role="alert">{error}</p> : null}

        <div className="social-login__divider"><span>안전한 소셜 로그인</span></div>
        <p className="social-login__legal">계속하면 Coordit의 <Link href="/terms">이용약관</Link>과 <Link href="/privacy">개인정보 처리방침</Link>을 확인한 것으로 간주합니다. 필수 동의는 다음 단계에서 직접 선택합니다.</p>
      </div>
    </AccountShell>
  );
}

export default function LoginPage() {
  return <Suspense fallback={<main className="auth-gate">로그인 화면을 준비하고 있어요.</main>}><LoginPageContent /></Suspense>;
}
