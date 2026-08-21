import Link from "next/link";
import { Logo } from "../../components/Logo";

export default function PrivacyPage() {
  return (
    <main className="legal-page">
      <header><Link href="/" aria-label="Coordit 홈으로 이동"><Logo size={24} /></Link><span>LEGAL · 2026.07.07</span></header>
      <article>
        <span className="account-shell__eyebrow">PRIVACY POLICY</span>
        <h1>개인정보 처리방침</h1>
        <p className="legal-page__lead">Coordit는 맞춤 핏 추천과 계정 운영에 필요한 최소한의 정보를 안전하게 처리합니다.</p>
        <h2>1. 수집하는 정보</h2>
        <p>소셜 로그인에서 제공되는 이메일, 사용자가 입력한 이름·성별·출생 연도와 선택한 신체 측정값을 처리합니다. 입력하지 않은 신체 정보는 저장하지 않습니다.</p>
        <h2>2. 이용 목적</h2>
        <p>계정 식별, 개인 핏 프로필 구성, 저장한 의류·사이즈 정보 관리, 서비스 안정성 개선에 사용합니다.</p>
        <h2>3. 보관 및 삭제</h2>
        <p>정보는 서비스 이용 기간 동안 보관하며, 사용자는 계정 설정 또는 고객 지원을 통해 자신의 정보와 계정 삭제를 요청할 수 있습니다.</p>
        <h2>4. 선택 동의</h2>
        <p>핏 데이터 개선과 마케팅 수신은 선택 사항입니다. 동의하지 않아도 핵심 핏 추천 서비스는 이용할 수 있습니다.</p>
      </article>
    </main>
  );
}
