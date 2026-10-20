import { useMemo, useState } from "react";
import { useNavigate, useSearchParams, Navigate } from "react-router-dom";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useTranslation } from "react-i18next";
import { Sparkles } from "lucide-react";
import { useAuth, NotAdminError } from "@/stores/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ThemeToggle } from "@/components/theme-toggle";
import { LocaleSwitcher } from "@/components/locale-switcher";
import { toast } from "@/components/ui/sonner";

type Values = { email: string; password: string };

export function LoginPage() {
  const { status, login } = useAuth();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { t } = useTranslation();
  const [submitting, setSubmitting] = useState(false);

  // Messages resolve through `t`, so the schema is rebuilt when the locale
  // changes — otherwise a switched language would keep the previous wording.
  const schema = useMemo(
    () =>
      z.object({
        email: z.string().email(t("login.emailInvalid")),
        password: z.string().min(1, t("login.passwordRequired")),
      }),
    [t],
  );

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<Values>({ resolver: zodResolver(schema), defaultValues: { email: "", password: "" } });

  if (status === "authed") {
    return <Navigate to={params.get("redirect") || "/dashboard"} replace />;
  }

  const onSubmit = async (values: Values) => {
    setSubmitting(true);
    try {
      await login(values.email, values.password);
      toast.success(t("login.welcome"));
      navigate(params.get("redirect") || "/dashboard", { replace: true });
    } catch (err) {
      if (err instanceof NotAdminError) {
        toast.error(t("login.notAdmin"));
      } else {
        toast.error(err instanceof Error ? err.message : t("login.failed"));
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="relative flex min-h-full items-center justify-center bg-background p-4">
      {/* Theme + language stay reachable before sign-in. */}
      <div className="absolute end-3 top-3 flex items-center gap-1">
        <LocaleSwitcher />
        <ThemeToggle />
      </div>

      <Card className="w-full max-w-sm">
        <CardHeader className="items-center text-center">
          <div className="mb-2 flex size-11 items-center justify-center rounded-xl bg-primary text-primary-foreground">
            <Sparkles className="size-5" />
          </div>
          <CardTitle className="text-xl">{t("brand")}</CardTitle>
          <CardDescription>{t("login.subtitle")}</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="email">{t("login.email")}</Label>
              <Input id="email" type="email" autoComplete="username" {...register("email")} />
              {errors.email && <p className="text-xs text-destructive">{errors.email.message}</p>}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="password">{t("login.password")}</Label>
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                {...register("password")}
              />
              {errors.password && (
                <p className="text-xs text-destructive">{errors.password.message}</p>
              )}
            </div>
            <Button type="submit" className="w-full" disabled={submitting}>
              {submitting ? t("login.signingIn") : t("login.signIn")}
            </Button>
          </form>
          <p className="mt-4 text-center text-xs text-muted-foreground">{t("login.hint")}</p>
        </CardContent>
      </Card>
    </div>
  );
}
