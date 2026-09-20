import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { envApi, whatsNewApi } from "@/api/admin";
import { ENVIRONMENTS, type Environment, type MobilePlatform, type WhatsNewCampaign, type WhatsNewContentPage } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
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
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const [platform, setPlatform] = useState<MobilePlatform>("ios");
  const activeEnv = environment ?? serverEnv.data?.environment;
  const query = useQuery({ queryKey: ["whats-new", activeEnv, platform], queryFn: ({ signal }) => whatsNewApi.list(activeEnv!, platform, signal), enabled: Boolean(activeEnv) });
  const [editing, setEditing] = useState<WhatsNewCampaign | null | undefined>(undefined);

  const remove = useMutation({ mutationFn: whatsNewApi.remove, onSuccess: () => { void qc.invalidateQueries({ queryKey: ["whats-new"] }); toast.success(t("content.deleted")); }, onError: (e) => toast.error(errorMessage(e)) });

  return <div className="space-y-6">
    <PageHeader title={t("whatsNew.title")} description={t("whatsNew.desc")} actions={<div className="flex gap-2">
      <Select value={activeEnv ?? ""} onValueChange={(v) => setEnvironment(v as Environment)}><SelectTrigger className="w-36"><SelectValue /></SelectTrigger><SelectContent>{ENVIRONMENTS.map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent></Select>
      <Select value={platform} onValueChange={(v) => setPlatform(v as MobilePlatform)}><SelectTrigger className="w-32"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="ios">iOS</SelectItem><SelectItem value="android">Android</SelectItem></SelectContent></Select>
      <Button disabled={!activeEnv} onClick={() => setEditing(null)}><Plus />{t("whatsNew.create")}</Button>
    </div>} />
    <Card><CardContent className="p-0"><Table><TableHeader><TableRow><TableHead>{t("content.name")}</TableHead><TableHead>{t("content.status")}</TableHead><TableHead>{t("whatsNew.version")}</TableHead><TableHead>{t("content.schedule")}</TableHead><TableHead>{t("content.operator")}</TableHead><TableHead className="text-right">{t("content.actions")}</TableHead></TableRow></TableHeader><TableBody>
      {(query.data?.items ?? []).map((item) => <TableRow key={item.id}><TableCell className="font-medium">{item.name}</TableCell><TableCell>{item.enabled ? t("content.enabled") : t("content.disabled")}</TableCell><TableCell>{item.min_app_version || "—"}</TableCell><TableCell className="text-xs">{item.starts_at ? new Date(item.starts_at).toLocaleString() : "—"}<br />{item.ends_at ? new Date(item.ends_at).toLocaleString() : "—"}</TableCell><TableCell>{item.updated_by || "—"}</TableCell><TableCell className="text-right"><Button variant="ghost" size="icon" onClick={() => setEditing(item)}><Pencil /></Button><Button variant="ghost" size="icon" onClick={() => window.confirm(t("whatsNew.deleteConfirm")) && remove.mutate(item.id)}><Trash2 /></Button></TableCell></TableRow>)}
      {!query.isLoading && !query.data?.items.length && <TableRow><TableCell colSpan={6} className="h-28 text-center text-muted-foreground">{t("whatsNew.empty")}</TableCell></TableRow>}
    </TableBody></Table></CardContent></Card>
    {activeEnv && editing !== undefined && <CampaignDialog campaign={editing} environment={activeEnv} platform={platform} onClose={() => setEditing(undefined)} onSaved={() => { setEditing(undefined); void qc.invalidateQueries({ queryKey: ["whats-new"] }); }} />}
  </div>;
}

function CampaignDialog({ campaign, environment, platform, onClose, onSaved }: { campaign: WhatsNewCampaign | null; environment: Environment; platform: MobilePlatform; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation();
  const [form, setForm] = useState<CampaignInput>(() => campaign ? { name: campaign.name, environment: campaign.environment, platform: campaign.platform, min_app_version: campaign.min_app_version, enabled: campaign.enabled, starts_at: campaign.starts_at, ends_at: campaign.ends_at, pages: campaign.pages } : freshCampaign(environment, platform));
  useEffect(() => setForm(campaign ? { name: campaign.name, environment: campaign.environment, platform: campaign.platform, min_app_version: campaign.min_app_version, enabled: campaign.enabled, starts_at: campaign.starts_at, ends_at: campaign.ends_at, pages: campaign.pages } : freshCampaign(environment, platform)), [campaign, environment, platform]);
  const save = useMutation({ mutationFn: () => campaign ? whatsNewApi.update(campaign.id, form) : whatsNewApi.create(form), onSuccess: () => { toast.success(t("content.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e)) });
  const patchPage = (index: number, patch: Partial<WhatsNewContentPage>) => setForm((v) => ({ ...v, pages: v.pages.map((p, i) => i === index ? { ...p, ...patch } : p) }));
  const patchCopy = (index: number, field: "title" | "body" | "cta_label", locale: "en" | "zh", value: string) => setForm((v) => ({ ...v, pages: v.pages.map((p, i) => i === index ? { ...p, [field]: { ...p[field], [locale]: value } } : p) }));
  const dateValue = (value: string | null) => value ? new Date(value).toISOString().slice(0, 16) : "";
  const setDate = (field: "starts_at" | "ends_at", value: string) => setForm((v) => ({ ...v, [field]: value ? new Date(value).toISOString() : null }));
  return <Dialog open onOpenChange={(open) => !open && onClose()}><DialogContent className="max-h-[90vh] max-w-4xl overflow-y-auto"><DialogHeader><DialogTitle>{campaign ? t("whatsNew.edit") : t("whatsNew.create")}</DialogTitle></DialogHeader>
    <div className="grid gap-4 md:grid-cols-2"><Field label={t("content.name")}><Input value={form.name} onChange={(e) => setForm((v) => ({ ...v, name: e.target.value }))} /></Field><Field label={t("whatsNew.version")}><Input value={form.min_app_version} onChange={(e) => setForm((v) => ({ ...v, min_app_version: e.target.value }))} /></Field><Field label={t("content.startsAt")}><Input type="datetime-local" value={dateValue(form.starts_at)} onChange={(e) => setDate("starts_at", e.target.value)} /></Field><Field label={t("content.endsAt")}><Input type="datetime-local" value={dateValue(form.ends_at)} onChange={(e) => setDate("ends_at", e.target.value)} /></Field><label className="flex items-center gap-3 text-sm"><input type="checkbox" checked={form.enabled} onChange={(e) => setForm((v) => ({ ...v, enabled: e.target.checked }))} />{t("content.enabled")}</label></div>
    {form.pages.map((page, index) => <Card key={`${page.id}-${index}`}><CardContent className="grid gap-3 p-4 md:grid-cols-2"><div className="md:col-span-2 flex items-center justify-between font-medium">{t("onboarding.page", { n: index + 1 })}<Button variant="ghost" size="icon" disabled={form.pages.length === 1} onClick={() => setForm((v) => ({ ...v, pages: v.pages.filter((_, i) => i !== index) }))}><Trash2 /></Button></div><Field label={t("content.identifier")}><Input value={page.id} onChange={(e) => patchPage(index, { id: e.target.value })} /></Field><Field label={t("content.imageUrl")}><Input value={page.image_url} onChange={(e) => patchPage(index, { image_url: e.target.value })} /></Field><Field label={`${t("content.title")} · English`}><Input value={page.title.en ?? ""} onChange={(e) => patchCopy(index, "title", "en", e.target.value)} /></Field><Field label={`${t("content.title")} · 简体中文`}><Input value={page.title.zh ?? ""} onChange={(e) => patchCopy(index, "title", "zh", e.target.value)} /></Field><Field label={`${t("content.body")} · English`}><Input value={page.body.en ?? ""} onChange={(e) => patchCopy(index, "body", "en", e.target.value)} /></Field><Field label={`${t("content.body")} · 简体中文`}><Input value={page.body.zh ?? ""} onChange={(e) => patchCopy(index, "body", "zh", e.target.value)} /></Field><Field label={t("whatsNew.action")}><Select value={page.cta_action || "close"} onValueChange={(cta_action) => patchPage(index, { cta_action: cta_action as WhatsNewContentPage["cta_action"] })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{["next", "close", "route", "url"].map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}</SelectContent></Select></Field><Field label={t("whatsNew.actionValue")}><Input value={page.cta_value} onChange={(e) => patchPage(index, { cta_value: e.target.value })} /></Field><Field label={`${t("whatsNew.actionLabel")} · English`}><Input value={page.cta_label.en ?? ""} onChange={(e) => patchCopy(index, "cta_label", "en", e.target.value)} /></Field><Field label={`${t("whatsNew.actionLabel")} · 简体中文`}><Input value={page.cta_label.zh ?? ""} onChange={(e) => patchCopy(index, "cta_label", "zh", e.target.value)} /></Field></CardContent></Card>)}
    <Button variant="outline" onClick={() => setForm((v) => ({ ...v, pages: [...v.pages, freshPage()] }))}><Plus />{t("onboarding.addPage")}</Button>
    <DialogFooter><Button variant="outline" onClick={onClose}>{t("content.cancel")}</Button><Button disabled={!form.name.trim() || save.isPending} onClick={() => save.mutate()}>{t("content.save")}</Button></DialogFooter>
  </DialogContent></Dialog>;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) { return <div className="space-y-2"><Label>{label}</Label>{children}</div>; }
