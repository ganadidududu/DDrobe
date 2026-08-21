"use client";

import type { Provider, Session } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { api, setApiToken } from "./api";
import { isSupabaseAuthConfigured, supabaseBrowser } from "./supabase-auth";

export type UserProfile = {
  readonly id: string;
  readonly email: string;
  readonly display_name: string | null;
  readonly gender: string | null;
  readonly birth_date: string | null;
  readonly birth_year: number | null;
  readonly created_at: string;
  readonly updated_at: string;
};

type OnboardingStatus = {
  readonly onboardingComplete: boolean;
};

interface AuthContextValue {
  readonly token: string | null;
  readonly userEmail: string | null;
  readonly userProfile: UserProfile | null;
  readonly isLoading: boolean;
  readonly isAuthenticated: boolean;
  readonly onboardingComplete: boolean | null;
  readonly isSupabaseAuthConfigured: boolean;
  readonly startSocialLogin: (provider: "google" | "apple", nextPath?: string) => Promise<void>;
  readonly refreshProfile: () => Promise<UserProfile | null>;
  readonly logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const AUTH_NEXT_KEY = "coordit.auth.next";

const readProfile = async (): Promise<UserProfile | null> => {
  try {
    return await api<UserProfile>("/users/me");
  } catch (error) {
    if (error instanceof Error) return null;
    throw error;
  }
};

const readOnboardingStatus = async (): Promise<boolean> => {
  try {
    const status = await api<OnboardingStatus>("/auth/onboarding/status");
    return status.onboardingComplete;
  } catch (error) {
    if (error instanceof Error) return false;
    throw error;
  }
};

export const AuthProvider = ({ children }: { readonly children: React.ReactNode }) => {
  const [token, setToken] = useState<string | null>(null);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [userProfile, setUserProfile] = useState<UserProfile | null>(null);
  const [onboardingComplete, setOnboardingComplete] = useState<boolean | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const clearAuth = useCallback((): void => {
    setApiToken(null);
    setToken(null);
    setUserEmail(null);
    setUserProfile(null);
    setOnboardingComplete(null);
  }, []);

  const syncSession = useCallback(async (session: Session | null): Promise<void> => {
    if (!session) {
      clearAuth();
      setIsLoading(false);
      return;
    }

    setApiToken(session.access_token);
    setToken(session.access_token);
    setUserEmail(session.user.email ?? null);
    const [profile, onboarding] = await Promise.all([readProfile(), readOnboardingStatus()]);
    setUserProfile(profile);
    setOnboardingComplete(onboarding);
    setIsLoading(false);
  }, [clearAuth]);

  useEffect(() => {
    if (!supabaseBrowser) {
      clearAuth();
      setIsLoading(false);
      return;
    }

    const browserClient = supabaseBrowser;
    let active = true;
    const initialize = async (): Promise<void> => {
      const { data, error } = await browserClient.auth.getSession();
      if (error || !active) {
        if (active) {
          clearAuth();
          setIsLoading(false);
        }
        return;
      }
      await syncSession(data.session);
    };

    void initialize();
    const { data: listener } = browserClient.auth.onAuthStateChange((_event, session) => {
      void syncSession(session);
    });

    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, [clearAuth, syncSession]);

  const refreshProfile = useCallback(async (): Promise<UserProfile | null> => {
    if (!token) return null;
    const [profile, onboarding] = await Promise.all([readProfile(), readOnboardingStatus()]);
    setUserProfile(profile);
    setOnboardingComplete(onboarding);
    return profile;
  }, [token]);

  const startSocialLogin = useCallback(async (
    provider: "google" | "apple",
    nextPath = "/closet"
  ): Promise<void> => {
    if (!supabaseBrowser) {
      throw new Error("소셜 로그인을 설정하는 중이에요. 잠시 후 다시 시도해 주세요.");
    }

    window.localStorage.setItem(AUTH_NEXT_KEY, nextPath);
    const socialProvider: Provider = provider;
    const { error } = await supabaseBrowser.auth.signInWithOAuth({
      provider: socialProvider,
      options: { redirectTo: `${window.location.origin}/auth/callback` }
    });
    if (error) throw error;
  }, []);

  const logout = useCallback(async (): Promise<void> => {
    if (supabaseBrowser) {
      const { error } = await supabaseBrowser.auth.signOut();
      if (error) throw error;
    }
    window.localStorage.removeItem(AUTH_NEXT_KEY);
    clearAuth();
  }, [clearAuth]);

  const value = useMemo<AuthContextValue>(() => ({
    token,
    userEmail,
    userProfile,
    isLoading,
    isAuthenticated: token !== null,
    onboardingComplete,
    isSupabaseAuthConfigured,
    startSocialLogin,
    refreshProfile,
    logout
  }), [isLoading, logout, onboardingComplete, refreshProfile, startSocialLogin, token, userEmail, userProfile]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export const useAuth = (): AuthContextValue => {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
};

export const getStoredAuthNextPath = (): string => {
  const nextPath = window.localStorage.getItem(AUTH_NEXT_KEY);
  return nextPath?.startsWith("/") ? nextPath : "/closet";
};

export const clearStoredAuthNextPath = (): void => {
  window.localStorage.removeItem(AUTH_NEXT_KEY);
};
