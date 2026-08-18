"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useState } from "react";
import { useAuth } from "../lib/auth-context";
import { Logo } from "./Logo";

const NAV_ITEMS = [
  { href: "/closet",    label: "Closet",   ko: "옷장" },
  { href: "/styling",   label: "Styling",  ko: "스타일링" },
  { href: "/fit",       label: "Fit Lab",  ko: "핏 분석" },
  { href: "/atelier",   label: "Atelier",  ko: "아뜰리에" },
];

export function TopBar() {
  const pathname = usePathname();
  const router   = useRouter();
  const { userEmail, userProfile, logout } = useAuth();
  const [showMenu, setShowMenu] = useState(false);

  const initial = userEmail ? userEmail.charAt(0).toUpperCase() : "인";
  const displayName = userProfile?.display_name ?? (userEmail ? userEmail.split("@")[0] : null);

  const handleLogout = async (): Promise<void> => {
    await logout();
    setShowMenu(false);
    router.push("/login");
  };

  return (
    <header style={{
      position: "sticky", top: 0, zIndex: 50,
      background: "rgba(245,240,230,0.85)",
      backdropFilter: "blur(20px)",
      borderBottom: "1px solid var(--line)",
      padding: "18px 48px",
      display: "flex", alignItems: "center", gap: 40,
    }}>
      <Link href="/" style={{ cursor: "pointer" }}>
        <Logo size={22} />
      </Link>

      <nav style={{ display: "flex", gap: 32, marginLeft: 24 }}>
        {NAV_ITEMS.map(item => {
          const active = pathname.startsWith(item.href);
          return (
            <Link key={item.href} href={item.href} style={{
              padding: "6px 2px",
              fontFamily: "var(--font-korean)",
              fontSize: 13, letterSpacing: "0.02em",
              color: active ? "var(--obsidian)" : "var(--text-muted)",
              borderBottom: active ? "1px solid var(--camel)" : "1px solid transparent",
              transition: "all 0.2s",
              textDecoration: "none",
            }}>
              <span style={{ fontFamily: "var(--font-display)", fontStyle: "italic", fontWeight: 500, marginRight: 6 }}>
                {item.label}
              </span>
              <span style={{ fontSize: 11, opacity: 0.7 }}>{item.ko}</span>
            </Link>
          );
        })}
      </nav>

      <div style={{ marginLeft: "auto", display: "flex", gap: 16, alignItems: "center" }}>
        <div style={{
          padding: "8px 14px",
          border: "1px solid var(--line-strong)",
          borderRadius: 20,
          fontSize: 11, color: "var(--text-muted)",
          fontFamily: "JetBrains Mono, monospace",
          letterSpacing: "0.1em",
          display: "flex", gap: 8, alignItems: "center",
        }}>
          <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--fit-perfect)" }} />
          AI ACTIVE
        </div>

        <div style={{
          width: 32, height: 32, borderRadius: "50%",
          background: "var(--walnut)", color: "var(--ivory)",
          display: "flex", alignItems: "center", justifyContent: "center",
          fontSize: 12, fontWeight: 600,
          fontFamily: "var(--font-display)", fontStyle: "italic",
        }}>
          {initial}
        </div>

        {userEmail ? (
          <div style={{ position: "relative" }}>
            <button
              onClick={() => setShowMenu(v => !v)}
              style={{ background: "none", border: "none", cursor: "pointer", fontSize: 11, fontFamily: "JetBrains Mono, monospace", color: "var(--text-muted)", letterSpacing: "0.08em" }}
            >
              {displayName} ▾
            </button>
            {showMenu && (
              <div style={{
                position: "absolute", top: "100%", right: 0, marginTop: 8,
                background: "var(--bg-raised)", border: "1px solid var(--line)",
                borderRadius: 4, padding: 8, minWidth: 160,
                boxShadow: "0 8px 24px rgba(0,0,0,0.1)", zIndex: 100,
              }}>
                <button
                  onClick={() => { router.push("/mypage"); setShowMenu(false); }}
                  style={{ display: "block", width: "100%", textAlign: "left", padding: "8px 12px", background: "none", border: "none", fontSize: 13, cursor: "pointer", color: "var(--obsidian)", fontFamily: "var(--font-korean)" }}
                >
                  마이페이지
                </button>
                <button
                  onClick={() => { router.push("/onboarding?mode=edit"); setShowMenu(false); }}
                  style={{ display: "block", width: "100%", textAlign: "left", padding: "8px 12px", background: "none", border: "none", fontSize: 13, cursor: "pointer", color: "var(--obsidian)", fontFamily: "var(--font-korean)" }}
                >
                  핏 프로필 설정
                </button>
                <button
                  onClick={() => void handleLogout()}
                  style={{ display: "block", width: "100%", textAlign: "left", padding: "8px 12px", background: "none", border: "none", fontSize: 13, cursor: "pointer", color: "var(--fit-tight)", fontFamily: "var(--font-korean)" }}
                >
                  로그아웃
                </button>
              </div>
            )}
          </div>
        ) : (
          <Link href="/login" style={{
            padding: "8px 16px", background: "var(--obsidian)", color: "var(--ivory)",
            border: "none", borderRadius: 4, fontSize: 12, cursor: "pointer",
            fontFamily: "var(--font-korean)", textDecoration: "none",
            display: "inline-block",
          }}>
            로그인
          </Link>
        )}
      </div>
    </header>
  );
}
