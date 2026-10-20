import { AppTranslationsEditor } from "@/components/app-translations-editor";
import { useEffect, useState } from "react";
import { Switch } from "@/components/ui/switch";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { onboardingApi } from "@/api/admin";
import type { Environment, MobilePlatform, OnboardingContentPage } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { ListActions, ListDetails, ListName } from "@/components/list-actions";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
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
  const platform: MobilePlatform = "app";
  const activeEnv: Environment = "prod";
  const query = useQuery({
    queryKey: ["onboarding", activeEnv, platform],
    queryFn: ({ signal }) => onboardingApi.get(activeEnv!, platform, signal),
    enabled: Boolean(activeEnv),
  });
  const [enabled, setEnabled] = useState(true);
  const [revision, setRevision] = useState(1);
  const [pages, setPages] = useState<OnboardingContentPage[]>([]);
  const [details, setDetails] = useState<{ page: OnboardingContentPage; index: number } | null>(null);
  const [editor, setEditor] = useState<{ page: OnboardingContentPage; index: number } | null>(null);

  useEffect(() => {
    if (!query.data) return;
    setEnabled(query.data.enabled);
    setRevision(query.data.revision);
    setPages(query.data.pages);
  }, [query.data]);

  const save = useMutation({
    mutationFn: (nextPages: OnboardingContentPage[] = pages) => onboardingApi.save(activeEnv!, platform, { enabled, revision, pages: nextPages }),
    onSuccess: (data) => {
      qc.setQueryData(["onboarding", activeEnv, platform], data);
      toast.success(t("content.saved"));
      setEditor(null);
      setDetails(null);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const patchPage = (patch: Partial<OnboardingContentPage>) => setEditor((current) => current ? { ...current, page: { ...current.page, ...patch } } : current);
  const patchCopy = (field: "title" | "body", locale: string, value: string) => setEditor((current) => current ? { ...current, page: { ...current.page, [field]: { ...current.page[field], [locale]: value, ...(locale === "zh-Hans" ? { zh: value } : locale === "zh-Hant" ? { zh_TW: value } : {}) } } } : current);

  return (
    <div className="space-y-6">
      <PageHeader title={t("onboarding.title")} description={t("onboarding.desc")} actions={
        <div className="flex gap-2">
          <span className="inline-flex h-9 items-center px-3 text-sm">App</span>
        </div>
      } />
      <Card>
        <CardHeader><CardTitle>{t("onboarding.settings")}</CardTitle><CardDescription>{t("onboarding.settingsDesc")}</CardDescription></CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <label className="flex items-center gap-3 text-sm"><Switch checked={enabled} onCheckedChange={setEnabled} />{t("content.enabled")}</label>
          <div className="space-y-2"><Label>{t("onboarding.revision")}</Label><Input type="number" min={1} value={revision} onChange={(e) => setRevision(Math.max(1, Number(e.target.value) || 1))} /></div>
        </CardContent>
      </Card>
      {query.isLoading ? <p className="text-sm text-muted-foreground">{t("common.loading")}</p> : pages.map((page, index) => (
        <Card key={`${page.id}-${index}`}>
          <CardHeader className="h-24 flex-row items-center justify-between"><div className="min-w-0"><CardTitle><ListName onClick={() => setDetails({ page, index })}>{page.title.en || page.title.zh || page.id}</ListName></CardTitle><CardDescription className="truncate">{page.id}</CardDescription></div><ListActions actions={[{ label: t("listActions.details"), onSelect: () => setDetails({ page, index }) }, { label: t("common.edit"), onSelect: () => setEditor({ page, index }) }]} /></CardHeader>
        </Card>
      ))}
      <div className="flex justify-between"><Button variant="outline" disabled={save.isPending} onClick={() => setEditor({ page: newPage(), index: pages.length })}><Plus />{t("onboarding.addPage")}</Button><Button disabled={!activeEnv || pages.length === 0 || save.isPending} onClick={() => save.mutate(pages)}>{t("content.save")}</Button></div>
      {details && <ListDetails title={details.page.title.en || details.page.id} onClose={() => setDetails(null)} fields={[{ label: t("content.identifier"), value: details.page.id }, { label: t("content.imageUrl"), value: details.page.image_url }, { label: t("content.title"), value: JSON.stringify(details.page.title, null, 2) }, { label: t("content.body"), value: JSON.stringify(details.page.body, null, 2) }]} actions={[{ label: t("common.edit"), onSelect: () => { setEditor(details); setDetails(null); } }, { label: t("common.delete"), icon: <Trash2 />, destructive: true, disabled: pages.length === 1 || save.isPending, onSelect: () => { if (window.confirm(t("common.delete"))) save.mutate(pages.filter((_, index) => index !== details.index)); } }]} />}
      <Dialog open={editor !== null} onOpenChange={(open) => { if (!open && !save.isPending) setEditor(null); }}><DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-2xl"><DialogHeader><DialogTitle>{t("common.edit")}</DialogTitle></DialogHeader>{editor && <div className="grid gap-4 md:grid-cols-2">
        <Field label={t("content.identifier")}><Input value={editor.page.id} onChange={(e) => patchPage({ id: e.target.value })} /></Field>
        <Field label={t("content.icon")}><Select value={editor.page.icon || "chat"} onValueChange={(icon) => patchPage({ icon })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{["chat", "life", "infinity", "memory"].map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent></Select></Field>
        <Field label={t("content.imageUrl")} wide><Input value={editor.page.image_url} onChange={(e) => patchPage({ image_url: e.target.value })} /></Field>
        <AppTranslationsEditor fields={[{ key: "title", label: t("content.title"), values: editor.page.title }, { key: "body", label: t("content.body"), values: editor.page.body, multiline: true }]} onChange={(field, locale, value) => patchCopy(field as "title" | "body", locale, value)} />
      </div>}<DialogFooter><Button variant="outline" disabled={save.isPending} onClick={() => setEditor(null)}>{t("common.cancel")}</Button><Button disabled={save.isPending || !editor?.page.id.trim()} onClick={() => { if (!editor) return; const next = [...pages]; next[editor.index] = editor.page; save.mutate(next); }}>{t("common.save")}</Button></DialogFooter></DialogContent></Dialog>
    </div>
  );
}

function Field({ label, children, wide }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return <div className={`space-y-2 ${wide ? "md:col-span-2" : ""}`}><Label>{label}</Label>{children}</div>;
}
