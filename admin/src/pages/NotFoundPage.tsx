import { Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";

export function NotFoundPage() {
  const { t } = useTranslation();
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-8 text-center">
      <p className="text-5xl font-bold tracking-tight">404</p>
      <p className="text-sm text-muted-foreground">{t("common.notFound")}</p>
      <Button asChild variant="outline">
        <Link to="/dashboard">{t("common.backToDashboard")}</Link>
      </Button>
    </div>
  );
}
