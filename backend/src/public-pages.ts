const pageStyles = `
  :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif; }
  * { box-sizing: border-box; }
  body { margin: 0; color: #172033; background: #f5f7fb; line-height: 1.7; word-break: keep-all; overflow-wrap: break-word; }
  header { padding: 56px 24px 44px; color: #fff; background: linear-gradient(135deg, #14213d, #29446f); }
  header div, main, footer { width: min(760px, calc(100% - 40px)); margin: 0 auto; }
  .brand { margin: 0 0 12px; color: #a9c2eb; font-size: 14px; font-weight: 700; letter-spacing: .14em; }
  h1 { margin: 0; font-size: clamp(32px, 7vw, 48px); line-height: 1.2; }
  header p { max-width: 620px; margin: 16px 0 0; color: #e5edf9; }
  main { padding: 32px 0 56px; }
  section { margin: 18px 0; padding: 24px; border: 1px solid #e1e6ef; border-radius: 18px; background: #fff; box-shadow: 0 10px 30px rgba(20,33,61,.05); }
  h2 { margin: 0 0 12px; color: #14213d; font-size: 21px; }
  h3 { margin: 20px 0 6px; color: #263a5d; font-size: 17px; }
  p, ul { margin: 8px 0; }
  ul { padding-left: 22px; }
  a { color: #275d9f; font-weight: 650; }
  .button { display: inline-block; margin-top: 12px; padding: 11px 16px; border-radius: 12px; color: #fff; background: #275d9f; text-decoration: none; }
  .muted { color: #667085; font-size: 14px; }
  .nowrap { white-space: nowrap; }
  footer { padding: 0 0 40px; color: #667085; font-size: 14px; }
  nav { display: flex; gap: 16px; flex-wrap: wrap; }
  @media (max-width: 520px) { header { padding-top: 40px; } section { padding: 20px; } }
`;

export const supportPageHtml = `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="COORDIT 앱 고객지원">
  <title>COORDIT 고객지원</title>
  <style>${pageStyles}</style>
</head>
<body>
  <header><div>
    <p class="brand">COORDIT</p>
    <h1>고객지원</h1>
    <p>앱 이용, 계정, <span class="nowrap">FIT LAB</span> 분석과 실타래 잔액에 관한 문의를 도와드립니다.</p>
  </div></header>
  <main>
    <section>
      <h2>문의하기</h2>
      <p>아래 이메일로 문의 내용과 사용 중인 기기, 앱 버전을 보내주세요. 계정 비밀번호나 결제정보 전체는 보내지 마세요.</p>
      <a class="button" href="mailto:insung6853@gmail.com">insung6853@gmail.com</a>
      <p class="muted">영업일 기준으로 순차 답변합니다.</p>
    </section>
    <section>
      <h2>자주 찾는 도움말</h2>
      <h3>로그인과 계정</h3>
      <p>Apple 또는 Google 계정으로 <span class="nowrap">로그인할 수 있습니다</span>. 로그인 문제가 계속되면 사용한 로그인 방식과 오류 화면을 함께 알려주세요.</p>
      <h3><span class="nowrap">FIT LAB</span> 결과</h3>
      <p>추천 사이즈와 핏 점수는 입력한 실측, 브랜드 측정 방식, 소재와 개인 선호에 따라 달라질 수 있는 참고 정보입니다.</p>
      <h3>계정 및 데이터 삭제</h3>
      <p>계정 삭제를 원하면 가입에 사용한 이메일과 함께 삭제 요청을 보내주세요. 본인 확인 후 관련 법령상 보관 의무가 있는 정보를 제외하고 처리합니다.</p>
    </section>
    <section>
      <h2>관련 문서</h2>
      <nav aria-label="관련 문서"><a href="/privacy">개인정보처리방침</a></nav>
    </section>
  </main>
  <footer>© 2026 COORDIT</footer>
</body>
</html>`;

export const privacyPageHtml = `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="COORDIT 개인정보처리방침">
  <title>COORDIT 개인정보처리방침</title>
  <style>${pageStyles}</style>
</head>
<body>
  <header><div>
    <p class="brand">COORDIT</p>
    <h1>개인정보처리방침</h1>
    <p>COORDIT은 서비스 제공에 필요한 정보만 처리하고, 이용자가 자신의 정보를 <span class="nowrap">통제할 수 있도록</span> 노력합니다.</p>
  </div></header>
  <main>
    <section>
      <h2>1. 처리하는 정보</h2>
      <ul>
        <li>계정 정보: 이름, 이메일, 사용자 식별자, Apple 또는 Google 로그인 정보</li>
        <li>프로필과 이용자 입력: 생년월일, 성별, 신체 치수, 옷장·상품·사이즈 정보, 사진 및 <span class="nowrap">FIT LAB</span> 입력·결과</li>
        <li>서비스 이용 정보: 기능 이용 기록, 구매·실타래 지급 기록, 앱 상호작용</li>
        <li>기기와 운영 정보: 기기 식별자, 대략적 위치, 광고 관련 데이터, 충돌·성능 진단 정보</li>
      </ul>
    </section>
    <section>
      <h2>2. 이용 목적</h2>
      <ul>
        <li>회원 인증, 프로필·옷장 저장과 계정 관리</li>
        <li><span class="nowrap">FIT LAB</span>의 사이즈 비교, 개인화된 추천과 결과 저장</li>
        <li>실타래 잔액, 구매 검증, 중복 지급 방지와 고객지원</li>
        <li>서비스 품질·성능 분석, 오류 대응, 부정 이용 방지와 보안</li>
        <li>동의 및 기능 활성화 상태에 따른 광고 제공과 광고 성과 측정</li>
      </ul>
    </section>
    <section>
      <h2>3. 외부 서비스와 처리 위탁</h2>
      <p>서비스 운영을 위해 Supabase(인증·데이터 저장), Apple 및 Google(로그인·결제), Google Cloud(서버 운영), OpenRouter 및 선택된 AI 모델 제공자(<span class="nowrap">FIT LAB</span> 생성), Google Mobile Ads(광고), 앱 안정성·분석 제공자를 <span class="nowrap">사용할 수 있습니다</span>. 각 제공자는 필요한 범위에서 정보를 처리하며 자체 정책과 법령을 따릅니다.</p>
    </section>
    <section>
      <h2>4. 보유 기간과 삭제</h2>
      <p>정보는 계정과 서비스 제공에 필요한 기간 동안 보유합니다. 탈퇴 또는 삭제 요청 시 지체 없이 삭제하거나 분리 보관하며, 전자상거래·세무·분쟁 대응 등 법령상 보관 의무가 있는 기록은 정해진 기간 동안 보관한 뒤 삭제합니다.</p>
    </section>
    <section>
      <h2>5. 이용자의 권리</h2>
      <p>이용자는 자신의 개인정보에 대한 열람, 정정, 삭제, 처리 정지와 동의 철회를 <span class="nowrap">요청할 수 있습니다</span>. 계정 삭제 및 개인정보 문의는 아래 연락처로 접수해 주세요.</p>
      <a class="button" href="mailto:insung6853@gmail.com">insung6853@gmail.com</a>
    </section>
    <section>
      <h2>6. 안전성 확보와 변경 안내</h2>
      <p>접근 권한 관리, 전송 구간 보호, 최소 권한 운영 등 합리적인 보호조치를 적용합니다. 중요한 내용이 변경되면 적용 전에 앱 또는 이 페이지를 통해 알립니다.</p>
      <p class="muted">시행일: <time datetime="2026-08-27">2026년 8월 27일</time></p>
      <nav aria-label="관련 문서"><a href="/support">고객지원으로 이동</a></nav>
    </section>
  </main>
  <footer>© 2026 COORDIT</footer>
</body>
</html>`;
