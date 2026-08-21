import Link from "next/link";
import { Logo } from "../../components/Logo";

export default function TermsPage() {
  return (
    <main className="legal-page">
      <header><Link href="/" aria-label="Coordit 홈으로 이동"><Logo size={24} /></Link><span>LEGAL · 2026.07.07</span></header>
      <article>
        <span className="account-shell__eyebrow">TERMS OF SERVICE</span>
        <h1>Coordit 이용약관</h1>
        <p className="legal-page__lead">Coordit는 사용자가 보유한 기준 의류와 제품 사이즈 정보를 비교해 핏 추천을 돕는 서비스입니다.</p>
        <h2>1. 서비스 이용</h2>
        <p>서비스 이용을 위해 Google 또는 Apple을 통한 본인 계정 인증이 필요합니다. 사용자는 정확한 정보를 제공하고 계정 접근 수단을 안전하게 관리해야 합니다.</p>
        <h2>2. 핏 추천의 성격</h2>
        <p>추천은 사용자가 입력한 측정값과 상품 정보에 기초한 참고 정보입니다. 소재, 세탁 상태, 브랜드 설계와 개인 선호에 따라 실제 착용감은 달라질 수 있습니다.</p>
        <h2>3. 이용 제한</h2>
        <p>타인의 계정을 사용하거나 서비스의 정상 동작을 방해하는 행위는 허용되지 않습니다. 안전한 서비스 운영을 위해 필요한 경우 이용을 제한할 수 있습니다.</p>
        <h2>4. 약관 변경</h2>
        <p>중요한 변경이 있을 경우 적용일과 변경 내용을 알리고, 필요한 경우 새 버전에 대한 동의를 요청합니다.</p>
      </article>
    </main>
  );
}
