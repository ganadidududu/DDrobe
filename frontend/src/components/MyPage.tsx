"use client";

import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { api } from "../lib/api";
import { useAuth, type UserProfile } from "../lib/auth-context";

type BodyMeasurement = {
  readonly height_cm: number | null;
  readonly weight_kg: number | null;
};

const genderLabel = (gender: string | null): string => {
  switch (gender) {
    case "female":
      return "여성";
    case "male":
      return "남성";
    case "prefer_not_to_say":
      return "응답하지 않음";
    default:
      return "미입력";
  }
};

export function MyPage() {
  const router = useRouter();
  const { userProfile, logout } = useAuth();
  const [profile, setProfile] = useState<UserProfile | null>(userProfile);
  const [measurement, setMeasurement] = useState<BodyMeasurement | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [showLogout, setShowLogout] = useState(false);

  useEffect(() => {
    const load = async (): Promise<void> => {
      try {
        const [nextProfile, measurements] = await Promise.all([
          api<UserProfile>("/users/me"),
          api<readonly BodyMeasurement[]>("/body-measurements")
        ]);
        setProfile(nextProfile);
        setMeasurement(measurements[0] ?? null);
      } catch (error) {
        if (error instanceof Error) setLoadError("일부 프로필 정보를 불러오지 못했어요.");
        else throw error;
      } finally {
        setLoading(false);
      }
    };
    void load();
  }, []);

  const profileItems = useMemo(
    () => [
      { label: "이메일", value: profile?.email ?? "불러오는 중" },
      { label: "성별", value: genderLabel(profile?.gender ?? null) },
      { label: "생일", value: profile?.birth_date ?? "미입력" },
      { label: "키", value: measurement?.height_cm ? `${measurement.height_cm}cm` : "나중에 입력" },
      { label: "몸무게", value: measurement?.weight_kg ? `${measurement.weight_kg}kg` : "나중에 입력" }
    ],
    [measurement, profile]
  );

  const handleLogout = async (): Promise<void> => {
    await logout();
    router.replace("/login");
  };

  return (
    <main className="mypage">
      <section className="mypage__hero">
        <div>
          <span className="account-shell__eyebrow">MY COORDIT · PRIVATE DOSSIER</span>
          <h1>{profile?.display_name ?? "나의"} <em>옷장 기록</em></h1>
          <p>핏 추천을 더 정확하게 만드는 개인 정보를 언제든 조정할 수 있어요.</p>
        </div>
        <button className="btn btn-secondary" onClick={() => router.push("/onboarding?mode=edit")}>정보 수정</button>
      </section>

      <section className="mypage__grid">
        <article className="mypage__profile-card">
          <div className="mypage__avatar" aria-hidden="true">{(profile?.display_name ?? profile?.email ?? "C").slice(0, 1).toUpperCase()}</div>
          <div>
            <span className="account-shell__eyebrow">PROFILE</span>
            <h2>{profile?.display_name ?? "프로필"}</h2>
            <p>{profile?.email}</p>
          </div>
          <div className="mypage__provider">GOOGLE · APPLE 계정으로 안전하게 로그인</div>
        </article>

        <article className="mypage__details">
          <div className="mypage__section-heading">
            <span className="account-shell__eyebrow">PERSONAL FIT DATA</span>
            <span>{loading ? "불러오는 중" : "저장됨"}</span>
          </div>
          {loadError ? <p className="account-form__notice account-form__notice--error" role="alert">{loadError}</p> : null}
          <dl>
            {profileItems.map((item) => (
              <div key={item.label}>
                <dt>{item.label}</dt>
                <dd>{item.value}</dd>
              </div>
            ))}
          </dl>
        </article>
      </section>

      <section className="mypage__account-actions">
        <div>
          <span className="account-shell__eyebrow">ACCOUNT</span>
          <h2>로그인과 계정 관리</h2>
          <p>현재 기기에서 안전하게 로그아웃할 수 있습니다.</p>
        </div>
        <button className="mypage__logout-button" onClick={() => setShowLogout(true)}>로그아웃</button>
      </section>

      {showLogout ? (
        <div className="account-dialog" role="dialog" aria-modal="true" aria-labelledby="logout-title">
          <div className="account-dialog__card">
            <span className="account-shell__eyebrow">SIGN OUT</span>
            <h2 id="logout-title">이 기기에서 로그아웃할까요?</h2>
            <p>저장된 옷장과 핏 기록은 그대로 유지됩니다. 다시 로그인하면 바로 이어서 사용할 수 있어요.</p>
            <div className="account-dialog__actions">
              <button className="btn btn-secondary" onClick={() => setShowLogout(false)}>계속 둘러보기</button>
              <button className="btn btn-primary" onClick={() => void handleLogout()}>로그아웃</button>
            </div>
          </div>
        </div>
      ) : null}
    </main>
  );
}
