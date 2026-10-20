import { AppTranslationsEditor } from "@/components/app-translations-editor";
import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { whatsNewApi } from "@/api/admin";
import { type Environment, type MobilePlatform, type WhatsNewCampaign, type WhatsNewContentPage } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { ListActions, ListDetails, ListName } from "@/components/list-actions";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/sonner";

type CampaignInput = Omit<WhatsNewCampaign, "id" | "updated_by" | "created_at" | "updated_at">;
const freshPage = (): WhatsNewContentPage => ({ id: `page-${Date.now()}`, image_url: "", icon: "memory", title: { en: "", zh: "" }, body: { en: "", zh: "" }, cta_label: { en: "Got it", zh: "知道了" }, cta_action: "close", cta_value: "" });
const freshCampaign = (environment: Environment, platform: MobilePlatform): CampaignInput => ({ name: "", environment, platform, min_app_version: "1.0.0", enabled: false, starts_at: null, ends_at: null, pages: [freshPage()] });

export function WhatsNewPage() {
  const { t } = useTranslation();
  const qc = useQueryClient();
  const platform: MobilePlatform = "app";
  const activeEnv: Environment = "prod";
  const query = useQuery({ queryKey: ["whats-new", activeEnv, platform], queryFn: ({ signal }) => whatsNewApi.list(activeEnv!, platform, signal), enabled: Boolean(activeEnv) });
  const [editing, setEditing] = useState<WhatsNewCampaign | null | undefined>(undefined);
  const [details, setDetails] = useState<WhatsNewCampaign | null>(null);
  const toggle = useMutation({
    mutationFn: ({ item, enabled }: { item: WhatsNewCampaign; enabled: boolean }) => whatsNewApi.update(item.id, { ...item, enabled }),
    onSuccess: async () => { toast.success(t("content.saved")); await qc.invalidateQueries({ queryKey: ["whats-new"] }); },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });

  const remove = useMutation({ mutationFn: whatsNewApi.remove, onSuccess: () => { void qc.invalidateQueries({ queryKey: ["whats-new"] }); toast.success(t("content.deleted")); }, onError: (e) => toast.error(errorMessage(e)) });

  return <div className="space-y-6">
    <PageHeader title={t("whatsNew.title")} description={t("whatsNew.desc")} actions={<div className="flex gap-2">
      <span className="inline-flex h-9 items-center px-3 text-sm">App</span>
      <Button disabled={!activeEnv} onClick={() => setEditing(null)}><Plus />{t("whatsNew.create")}</Button>
    </div>} />
    <Card><CardContent className="p-0"><Table><TableHeader><TableRow><TableHead>{t("content.name")}</TableHead><TableHead>{t("content.status")}</TableHead><TableHead>{t("whatsNew.version")}</TableHead><TableHead>{t("content.schedule")}</TableHead><TableHead>{t("content.operator")}</TableHead><TableHead className="text-right">{t("content.actions")}</TableHead></TableRow></TableHeader><TableBody>
      {(query.data?.items ?? []).map((item) => <TableRow key={item.id}><TableCell><ListName onClick={() => setDetails(item)}>{item.name}</ListName></TableCell><TableCell><Switch checked={item.enabled} disabled={toggle.isPending} aria-label={t("content.enabled")} onCheckedChange={(enabled) => toggle.mutate({ item, enabled })} /></TableCell><TableCell>{item.min_app_version || "—"}</TableCell><TableCell className="text-xs">{item.starts_at ? new Date(item.starts_at).toLocaleString() : "—"}<br />{item.ends_at ? new Date(item.ends_at).toLocaleString() : "—"}</TableCell><TableCell>{item.updated_by || "—"}</TableCell><TableCell className="text-end"><ListActions actions={[{ label: t("listActions.details"), onSelect: () => setDetails(item) }, { label: t("common.edit"), icon: <Pencil />, onSelect: () => setEditing(item) }]} /></TableCell></TableRow>)}
      {!query.isLoading && !query.data?.items.length && <TableRow><TableCell colSpan={6} className="h-28 text-center text-muted-foreground">{t("whatsNew.empty")}</TableCell></TableRow>}
    </TableBody></Table></CardContent></Card>
    {activeEnv && editing !== undefined && <CampaignDialog campaign={editing} environment={activeEnv} platform={platform} onClose={() => setEditing(undefined)} onSaved={() => { setEditing(undefined); void qc.invalidateQueries({ queryKey: ["whats-new"] }); }} />}
    {details && <ListDetails title={details.name} onClose={() => setDetails(null)} fields={[{ label: t("whatsNew.version"), value: details.min_app_version }, { label: t("content.schedule"), value: `${details.starts_at || "—"} / ${details.ends_at || "—"}` }, { label: t("content.body"), value: JSON.stringify(details.pages, null, 2) }]} actions={[{ label: t("common.edit"), icon: <Pencil />, onSelect: () => { setEditing(details); setDetails(null); } }, { label: t("common.delete"), destructive: true, icon: <Trash2 />, disabled: remove.isPending, onSelect: () => { if (window.confirm(t("whatsNew.deleteConfirm"))) { remove.mutate(details.id); setDetails(null); } } }]} />}
  </div>;
}

function CampaignDialog({ campaign, environment, platform, onClose, onSaved }: { campaign: WhatsNewCampaign | null; environment: Environment; platform: MobilePlatform; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation();
  const [form, setForm] = useState<CampaignInput>(() => campaign ? { name: campaign.name, environment: campaign.environment, platform: "app", min_app_version: campaign.min_app_version, enabled: campaign.enabled, starts_at: campaign.starts_at, ends_at: campaign.ends_at, pages: campaign.pages } : freshCampaign(environment, platform));
  useEffect(() => setForm(campaign ? { name: campaign.name, environment: campaign.environment, platform: "app", min_app_version: campaign.min_app_version, enabled: campaign.enabled, starts_at: campaign.starts_at, ends_at: campaign.ends_at, pages: campaign.pages } : freshCampaign(environment, platform)), [campaign, environment, platform]);
  const save = useMutation({ mutationFn: () => campaign ? whatsNewApi.update(campaign.id, form) : whatsNewApi.create(form), onSuccess: () => { toast.success(t("content.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e)) });
  const patchPage = (index: number, patch: Partial<WhatsNewContentPage>) => setForm((v) => ({ ...v, pages: v.pages.map((p, i) => i === index ? { ...p, ...patch } : p) }));
  const patchCopy = (index: number, field: "title" | "body" | "cta_label", locale: string, value: string) => setForm((v) => ({ ...v, pages: v.pages.map((p, i) => i === index ? { ...p, [field]: { ...p[field], [locale]: value, ...(locale === "zh-Hans" ? {zh: value} : locale === "zh-Hant" ? {zh_TW: value} : {}) } } : p) }));
  const dateValue = (value: string | null) => value ? new Date(value).toISOString().slice(0, 16) : "";
  const setDate = (field: "starts_at" | "ends_at", value: string) => setForm((v) => ({ ...v, [field]: value ? new Date(value).toISOString() : null }));
  return <Dialog open onOpenChange={(open) => !open && onClose()}><DialogContent className="max-h-[90vh] max-w-4xl overflow-y-auto"><DialogHeader><DialogTitle>{campaign ? t("whatsNew.edit") : t("whatsNew.create")}</DialogTitle></DialogHeader>
    <div className="grid gap-4 md:grid-cols-2"><Field label={t("content.name")}><Input value={form.name} onChange={(e) => setForm((v) => ({ ...v, name: e.target.value }))} /></Field><Field label={t("whatsNew.version")}><Input value={form.min_app_version} onChange={(e) => setForm((v) => ({ ...v, min_app_version: e.target.value }))} /></Field><Field label={t("content.startsAt")}><Input type="datetime-local" value={dateValue(form.starts_at)} onChange={(e) => setDate("starts_at", e.target.value)} /></Field><Field label={t("content.endsAt")}><Input type="datetime-local" value={dateValue(form.ends_at)} onChange={(e) => setDate("ends_at", e.target.value)} /></Field><label className="flex items-center gap-3 text-sm"><Switch checked={form.enabled} onCheckedChange={(checked) => setForm((v) => ({ ...v, enabled: checked }))} />{t("content.enabled")}</label></div>
    {form.pages.map((page, index) => <Card key={`${page.id}-${index}`}><CardContent className="grid gap-3 p-4 md:grid-cols-2"><div className="md:col-span-2 flex items-center justify-between font-medium">{t("onboarding.page", { n: index + 1 })}<Button variant="ghost" size="icon" disabled={form.pages.length === 1} onClick={() => setForm((v) => ({ ...v, pages: v.pages.filter((_, i) => i !== index) }))}><Trash2 /></Button></div><Field label={t("content.identifier")}><Input value={page.id} onChange={(e) => patchPage(index, { id: e.target.value })} /></Field><Field label={t("content.imageUrl")}><Input value={page.image_url} onChange={(e) => patchPage(index, { image_url: e.target.value })} /></Field><AppTranslationsEditor fields={[{key: "title", label: t("content.title"), values: page.title}, {key: "body", label: t("content.body"), values: page.body, multiline: true}, {key: "cta_label", label: t("whatsNew.actionLabel"), values: page.cta_label}]} onChange={(field, locale, value) => patchCopy(index, field as "title" | "body" | "cta_label", locale, value)} /><Field label={t("whatsNew.action")}><Select value={page.cta_action || "close"} onValueChange={(cta_action) => patchPage(index, { cta_action: cta_action as WhatsNewContentPage["cta_action"] })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{["next", "close", "route", "url"].map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent></Select></Field><Field label={t("whatsNew.actionValue")}><Input value={page.cta_value} onChange={(e) => patchPage(index, { cta_value: e.target.value })} /></Field></CardContent></Card>)}
    <Button variant="outline" onClick={() => setForm((v) => ({ ...v, pages: [...v.pages, freshPage()] }))}><Plus />{t("onboarding.addPage")}</Button>
    <DialogFooter><Button variant="outline" onClick={onClose}>{t("content.cancel")}</Button><Button disabled={!form.name.trim() || save.isPending} onClick={() => save.mutate()}>{t("content.save")}</Button></DialogFooter>
  </DialogContent></Dialog>;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) { return <div className="space-y-2"><Label>{label}</Label>{children}</div>; }
