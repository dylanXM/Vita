import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { envApi, onboardingApi } from "@/api/admin";
import type { Environment, MobilePlatform, OnboardingContentPage } from "@/api/types";
import { ENVIRONMENTS } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "@/components/ui/sonner";

const newPage = (): OnboardingContentPage => ({
  id: `page-${Date.now()}`,
  image_url: "",
  icon: "chat",
  title: { en: "", zh: "" },
  body: { en: "", zh: "" },
});

export function OnboardingPage() {
  const { t } = useTranslation();
  const qc = useQueryClient();
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const [platform, setPlatform] = useState<MobilePlatform>("ios");
  const activeEnv = environment ?? serverEnv.data?.environment;
  const query = useQuery({
    queryKey: ["onboarding", activeEnv, platform],
    queryFn: ({ signal }) => onboardingApi.get(activeEnv!, platform, signal),
    enabled: Boolean(activeEnv),
  });
  const [enabled, setEnabled] = useState(true);
  const [revision, setRevision] = useState(1);
  const [pages, setPages] = useState<OnboardingContentPage[]>([]);

  useEffect(() => {
    if (!query.data) return;
    setEnabled(query.data.enabled);
    setRevision(query.data.revision);
    setPages(query.data.pages);
  }, [query.data]);

  const save = useMutation({
    mutationFn: () => onboardingApi.save(activeEnv!, platform, { enabled, revision, pages }),
    onSuccess: (data) => {
      qc.setQueryData(["onboarding", activeEnv, platform], data);
      toast.success(t("content.saved"));
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const patchPage = (index: number, patch: Partial<OnboardingContentPage>) =>
    setPages((current) => current.map((page, i) => (i === index ? { ...page, ...patch } : page)));
  const patchCopy = (index: number, field: "title" | "body", locale: "en" | "zh", value: string) =>
    setPages((current) => current.map((page, i) => i === index ? { ...page, [field]: { ...page[field], [locale]: value } } : page));

  return (
    <div className="space-y-6">
      <PageHeader title={t("onboarding.title")} description={t("onboarding.desc")} actions={
        <div className="flex gap-2">
          <Select value={activeEnv ?? ""} onValueChange={(v) => setEnvironment(v as Environment)}><SelectTrigger className="w-36"><SelectValue /></SelectTrigger><SelectContent>{ENVIRONMENTS.map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent></Select>
          <Select value={platform} onValueChange={(v) => setPlatform(v as MobilePlatform)}><SelectTrigger className="w-32"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="ios">iOS</SelectItem><SelectItem value="android">Android</SelectItem></SelectContent></Select>
        </div>
      } />
      <Card>
        <CardHeader><CardTitle>{t("onboarding.settings")}</CardTitle><CardDescription>{t("onboarding.settingsDesc")}</CardDescription></CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <label className="flex items-center gap-3 text-sm"><input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />{t("content.enabled")}</label>
          <div className="space-y-2"><Label>{t("onboarding.revision")}</Label><Input type="number" min={1} value={revision} onChange={(e) => setRevision(Math.max(1, Number(e.target.value) || 1))} /></div>
        </CardContent>
      </Card>
      {query.isLoading ? <p className="text-sm text-muted-foreground">{t("common.loading")}</p> : pages.map((page, index) => (
        <Card key={`${page.id}-${index}`}>
          <CardHeader className="flex-row items-start justify-between"><div><CardTitle>{t("onboarding.page", { n: index + 1 })}</CardTitle><CardDescription>{page.id}</CardDescription></div><Button variant="ghost" size="icon" disabled={pages.length === 1} onClick={() => setPages((v) => v.filter((_, i) => i !== index))}><Trash2 /></Button></CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-2">
            <Field label={t("content.identifier")}><Input value={page.id} onChange={(e) => patchPage(index, { id: e.target.value })} /></Field>
            <Field label={t("content.icon")}><Select value={page.icon || "chat"} onValueChange={(icon) => patchPage(index, { icon })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{["chat", "life", "infinity", "memory"].map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent></Select></Field>
            <Field label={t("content.imageUrl")} wide><Input value={page.image_url} onChange={(e) => patchPage(index, { image_url: e.target.value })} placeholder="https://…" /></Field>
            <Field label={`${t("content.title")} · English`}><Input value={page.title.en ?? ""} onChange={(e) => patchCopy(index, "title", "en", e.target.value)} /></Field>
            <Field label={`${t("content.title")} · 简体中文`}><Input value={page.title.zh ?? ""} onChange={(e) => patchCopy(index, "title", "zh", e.target.value)} /></Field>
            <Field label={`${t("content.body")} · English`}><textarea className="min-h-24 w-full rounded-md border bg-background p-3 text-sm" value={page.body.en ?? ""} onChange={(e) => patchCopy(index, "body", "en", e.target.value)} /></Field>
            <Field label={`${t("content.body")} · 简体中文`}><textarea className="min-h-24 w-full rounded-md border bg-background p-3 text-sm" value={page.body.zh ?? ""} onChange={(e) => patchCopy(index, "body", "zh", e.target.value)} /></Field>
          </CardContent>
        </Card>
      ))}
      <div className="flex justify-between"><Button variant="outline" onClick={() => setPages((v) => [...v, newPage()])}><Plus />{t("onboarding.addPage")}</Button><Button disabled={!activeEnv || pages.length === 0 || save.isPending} onClick={() => save.mutate()}>{t("content.save")}</Button></div>
    </div>
  );
}

function Field({ label, children, wide }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return <div className={`space-y-2 ${wide ? "md:col-span-2" : ""}`}><Label>{label}</Label>{children}</div>;
}
