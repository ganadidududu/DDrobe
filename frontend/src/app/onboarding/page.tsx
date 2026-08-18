"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { AccountShell } from "../../components/AccountShell";
import { api } from "../../lib/api";
import { useAuth } from "../../lib/auth-context";

const CONSENT_VERSION = "2026-07-07";

const steps = [
  { number: "01", label: "프로필" },
  { number: "02", label: "핏 정보" },
  { number: "03", label: "약관 동의" }
] as const;

type MeasurementKey = "heightCm" | "weightKg";

type OnboardingResponse = {
  readonly onboardingComplete: true;
};

const measurementFields: readonly { readonly key: MeasurementKey; readonly label: string; readonly unit: string; readonly hint: string }[] = [
  { key: "heightCm", label: "키", unit: "cm", hint: "예: 170" },
  { key: "weightKg", label: "몸무게", unit: "kg", hint: "예: 58" }
];

function OnboardingPageContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { userProfile, refreshProfile } = useAuth();
  const [step, setStep] = useState(1);
  const [displayName, setDisplayName] = useState("");
  const [gender, setGender] = useState("");
  const [birthDate, setBirthDate] = useState("");
  const [measurements, setMeasurements] = useState<Record<MeasurementKey, string>>({
    heightCm: "",
    weightKg: ""
  });
  const [consents, setConsents] = useState({ terms: false, privacy: false, fitData: false, marketing: false });
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const isEdit = searchParams.get("mode") === "edit";
  const nextPath = searchParams.get("next")?.startsWith("/") ? searchParams.get("next") ?? "/closet" : "/closet";

  useEffect(() => {
    if (!userProfile) return;
    setDisplayName(userProfile.display_name ?? "");
    setGender(userProfile.gender ?? "");
    setBirthDate(userProfile.birth_date ?? "");
  }, [userProfile]);

  const goTo = (nextStep: number): void => {
    if (nextStep === 2 && !displayName.trim()) {
      setError("옷장 기록에 표시할 이름을 입력해 주세요.");
      return;
    }
    setError("");
    setStep(nextStep);
  };

  const setMeasurement = (key: MeasurementKey, value: string): void => {
    setMeasurements((current) => ({ ...current, [key]: value }));
  };

  const submit = async (): Promise<void> => {
    if (!consents.terms || !consents.privacy) {
      setError("서비스 이용약관과 개인정보 처리방침에 모두 동의해 주세요.");
      return;
    }

    setSaving(true);
    setError("");
    try {
      await api<OnboardingResponse>("/auth/onboarding", {
        method: "POST",
        body: {
          displayName: displayName.trim(),
          gender: gender || undefined,
          birthDate: birthDate || undefined,
          bodyMeasurements: measurements,
          consents: {
            terms_of_service: { accepted: true, version: CONSENT_VERSION },
            privacy_policy: { accepted: true, version: CONSENT_VERSION },
            fit_data_improvement: { accepted: consents.fitData, version: CONSENT_VERSION },
            marketing: { accepted: consents.marketing, version: CONSENT_VERSION }
          }
        }
      });
      await refreshProfile();
      router.replace(isEdit ? "/mypage" : nextPath);
    } catch (submitError) {
      if (submitError instanceof Error) setError(submitError.message);
      else setError("설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <AccountShell
      eyebrow={isEdit ? "MY COORDIT · PROFILE SETTINGS" : "MY COORDIT · FIRST SETUP"}
      title={isEdit ? <>내 핏 기록을<br /><em>다듬어요.</em></> : <>내 핏 기록을 위한<br /><em>첫 설정.</em></>}
      summary={isEdit ? "프로필과 선택한 측정값은 언제든 바꿀 수 있어요." : "필수 정보는 가볍게, 핏 정보는 원하는 만큼. 입력하지 않은 정보는 나중에 마이페이지에서 이어갈 수 있어요."}
      step={step}
    >
      <div className="onboarding">
        <ol className="onboarding__steps" aria-label="초기 설정 단계">
          {steps.map((item, index) => (
            <li key={item.number} className={step === index + 1 ? "is-current" : step > index + 1 ? "is-complete" : ""}>
              <span>{item.number}</span><strong>{item.label}</strong>
            </li>
          ))}
        </ol>

        {step === 1 ? (
          <section className="account-form">
            <div className="account-form__heading"><span className="account-shell__eyebrow">01 · PROFILE</span><h2>어떻게 불러드릴까요?</h2><p>이 이름은 나의 옷장과 핏 리포트에만 표시됩니다.</p></div>
            <label className="account-field"><span>이름 또는 별명 <b>필수</b></span><input value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="예: 민아" autoComplete="name" maxLength={40} /></label>
            <fieldset className="account-choice"><legend>성별 <small>선택</small></legend><div className="account-choice__grid">
              {[{ value: "female", label: "여성" }, { value: "male", label: "남성" }, { value: "prefer_not_to_say", label: "응답하지 않음" }].map((option) => (
                <label key={option.value}><input type="radio" name="gender" value={option.value} checked={gender === option.value} onChange={() => setGender(option.value)} /><span>{option.label}</span></label>
              ))}
            </div></fieldset>
            <label className="account-field"><span>생일 <small>선택</small></span><input type="date" value={birthDate} onChange={(event) => setBirthDate(event.target.value)} /></label>
            <div className="account-form__footer"><p>성별과 생일은 추천의 기본 맥락으로만 활용합니다.</p><button className="btn btn-primary" onClick={() => goTo(2)}>다음 단계</button></div>
          </section>
        ) : null}

        {step === 2 ? (
          <section className="account-form">
            <div className="account-form__heading"><span className="account-shell__eyebrow">02 · OPTIONAL FIT DATA</span><h2>체형을 기록해 볼까요?</h2><p>선택 입력입니다. 지금은 키만 입력하거나, 모두 건너뛰어도 괜찮아요.</p></div>
            <div className="measurement-grid">{measurementFields.map((field) => <label className="account-field" key={field.key}><span>{field.label} <small>{field.unit}</small></span><input type="number" inputMode="decimal" min="0" value={measurements[field.key]} onChange={(event) => setMeasurement(field.key, event.target.value)} placeholder={field.hint} /><i>{field.unit}</i></label>)}</div>
            <div className="account-form__footer account-form__footer--split"><button className="btn btn-secondary" onClick={() => goTo(1)}>이전</button><div><button className="account-text-button" onClick={() => goTo(3)}>나중에 입력하기</button><button className="btn btn-primary" onClick={() => goTo(3)}>저장하고 다음</button></div></div>
          </section>
        ) : null}

        {step === 3 ? (
          <section className="account-form">
            <div className="account-form__heading"><span className="account-shell__eyebrow">03 · CONSENT</span><h2>마지막으로 확인해 주세요.</h2><p>필수 약관 동의 후에만 개인 옷장과 핏 데이터를 안전하게 저장할 수 있어요.</p></div>
            <div className="consent-list">
              <label className="consent-row consent-row--all"><input type="checkbox" checked={consents.terms && consents.privacy && consents.fitData && consents.marketing} onChange={(event) => setConsents({ terms: event.target.checked, privacy: event.target.checked, fitData: event.target.checked, marketing: event.target.checked })} /><span><b>모두 동의</b><small>선택 동의를 포함하며, 개별 선택도 가능합니다.</small></span></label>
              <label className="consent-row"><input type="checkbox" checked={consents.terms} onChange={(event) => setConsents((current) => ({ ...current, terms: event.target.checked }))} /><span><b>[필수] 서비스 이용약관</b><small>계정 이용과 핏 추천 서비스의 기본 약관</small></span><Link href="/terms" target="_blank">보기</Link></label>
              <label className="consent-row"><input type="checkbox" checked={consents.privacy} onChange={(event) => setConsents((current) => ({ ...current, privacy: event.target.checked }))} /><span><b>[필수] 개인정보 처리방침</b><small>프로필과 선택한 신체 정보의 처리 기준</small></span><Link href="/privacy" target="_blank">보기</Link></label>
              <label className="consent-row"><input type="checkbox" checked={consents.fitData} onChange={(event) => setConsents((current) => ({ ...current, fitData: event.target.checked }))} /><span><b>[선택] 핏 데이터 개선</b><small>더 나은 추천 품질을 위한 익명화된 분석 활용</small></span></label>
              <label className="consent-row"><input type="checkbox" checked={consents.marketing} onChange={(event) => setConsents((current) => ({ ...current, marketing: event.target.checked }))} /><span><b>[선택] 새로운 기능 및 소식 받기</b><small>제품 업데이트와 개인화 팁 안내</small></span></label>
            </div>
            {error ? <p className="account-form__notice account-form__notice--error" role="alert">{error}</p> : null}
            <div className="account-form__footer account-form__footer--split"><button className="btn btn-secondary" onClick={() => goTo(2)}>이전</button><button className="btn btn-primary" onClick={() => void submit()} disabled={saving}>{saving ? "저장 중" : isEdit ? "변경사항 저장" : "나의 옷장 시작하기"}</button></div>
          </section>
        ) : null}
      </div>
    </AccountShell>
  );
}

export default function OnboardingPage() {
  return <Suspense fallback={<main className="auth-gate">설정 화면을 준비하고 있어요.</main>}><OnboardingPageContent /></Suspense>;
}
