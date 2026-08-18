import type { Metadata } from "next";
import Script from "next/script";
import type { ReactNode } from "react";
import { AuthRouteGuard } from "../components/AuthRouteGuard";
import { AuthProvider } from "../lib/auth-context";
import "../styles/globals.css";

export const metadata: Metadata = {
  title: "Coordit — The Curated Wardrobe",
  description: "기준 옷 기반 핏 분석 · 개인화 옷장 큐레이션",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ko">
      <head>
        {process.env.NODE_ENV === "development" && (
          <>
            <Script
              src="//unpkg.com/react-grab/dist/index.global.js"
              crossOrigin="anonymous"
              strategy="beforeInteractive"
            />
            <Script
              src="//unpkg.com/react-scan/dist/auto.global.js"
              crossOrigin="anonymous"
              strategy="afterInteractive"
            />
          </>
        )}
      </head>
      <body>
        <AuthProvider><AuthRouteGuard>{children}</AuthRouteGuard></AuthProvider>
      </body>
    </html>
  );
}
