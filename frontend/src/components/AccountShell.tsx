"use client";

import { useRouter } from "next/navigation";
import type { ReactNode } from "react";
import { Logo } from "./Logo";

type AccountShellProps = {
  readonly eyebrow: string;
  readonly title: ReactNode;
  readonly summary: string;
  readonly step?: number;
  readonly children: ReactNode;
};

export function AccountShell({ eyebrow, title, summary, step, children }: AccountShellProps) {
  const router = useRouter();

  return (
    <main className="account-shell">
      <header className="account-shell__header">
        <button className="account-shell__brand" onClick={() => router.push("/")} aria-label="Coordit 홈으로 이동">
          <Logo size={24} />
        </button>
        <span className="account-shell__header-label">THE CURATED WARDROBE</span>
        {step ? <span className="account-shell__step">SETUP {String(step).padStart(2, "0")} / 03</span> : null}
      </header>

      <div className="account-shell__content">
        <aside className="account-shell__aside">
          <span className="account-shell__eyebrow">{eyebrow}</span>
          <h1>{title}</h1>
          <p>{summary}</p>
          <div className="account-shell__seal" aria-hidden="true">
            <span>COORDIT</span>
            <span>PRIVATE FIT FILE</span>
          </div>
        </aside>
        <section className="account-shell__panel">{children}</section>
      </div>
    </main>
  );
}
