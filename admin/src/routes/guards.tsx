import { Navigate, useLocation } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useAuth } from "@/stores/auth";
import { Sparkles } from "lucide-react";

function FullScreenLoader() {
  const { t } = useTranslation();
  return (
    <div className="flex h-full items-center justify-center">
      <div className="flex items-center gap-2 text-muted-foreground">
        <Sparkles className="size-5 animate-pulse text-primary" />
        <span className="text-sm">{t("common.loading")}</span>
      </div>
    </div>
  );
}

/** Gate for admin-only routes: bounces anon users to /login. */
export function RequireAuth({ children }: { children: React.ReactNode }) {
  const status = useAuth((s) => s.status);
  const location = useLocation();

  if (status === "loading") return <FullScreenLoader />;
  if (status === "anon") {
    const redirect = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/login?redirect=${redirect}`} replace />;
  }
  return <>{children}</>;
}
