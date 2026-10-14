import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Headphones, Image, MessageCircle, Plus, Save, Trash2, Video } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router-dom";

import { agentApi } from "@/api/admin";
import type { AIModel, MediaModelRoute, MediaModelType } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { ListActions, ListDetails, ListName } from "@/components/list-actions";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { toast } from "@/components/ui/sonner";
import { compatibleMediaModels, selectedMediaModelIDs } from "./media-model-routes";

const groups: Array<{ type: MediaModelType; icon: typeof Image }> = [
  { type: "text", icon: MessageCircle },
  { type: "image", icon: Image },
  { type: "audio", icon: Headphones },
  { type: "video", icon: Video },
];

export function MediaModelsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["media-model-routes"], queryFn: ({ signal }) => agentApi.mediaRoutes(signal) });
  const [routes, setRoutes] = useState<MediaModelRoute[]>([]);
  const [activeType, setActiveType] = useState<MediaModelType>("text");
  useEffect(() => { if (query.data) setRoutes(query.data.routes); }, [query.data]);
  const save = useMutation({
    mutationFn: (next: MediaModelRoute) => agentApi.saveMediaRoutes([next]),
    onSuccess: (data) => {
      queryClient.setQueryData(["media-model-routes"], data);
      setRoutes(data.routes);
      toast.success(t("mediaModels.saved"));
      void queryClient.invalidateQueries({ queryKey: ["agent-config"] });
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  if (query.isLoading) return <Skeleton className="h-96" />;
  if (!query.data || query.isError) return <p className="text-sm text-destructive">{t("common.failedToLoad")}</p>;
  return (
    <div className="space-y-6">
      <PageHeader title={t("mediaModels.title")} description={t("mediaModels.description")} />
      <div className="flex gap-1 overflow-x-auto rounded-lg border bg-muted/40 p-1" role="tablist" aria-label={t("mediaModels.title")}>
        {groups.map(({ type, icon: Icon }) => <button key={type} type="button" role="tab" aria-selected={activeType === type} onClick={() => setActiveType(type)} className={`flex min-w-24 flex-1 items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-medium transition-colors ${activeType === type ? "bg-background text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"}`}><Icon className="size-4" />{t(`mediaModels.type.${type}`)}</button>)}
      </div>
      {groups.filter(({ type }) => type === activeType).map(({ type, icon: Icon }) => <Card key={type} role="tabpanel">
        <CardHeader><CardTitle className="flex items-center gap-2"><Icon className="size-5" />{t(`mediaModels.type.${type}`)}</CardTitle><CardDescription>{t(`mediaModels.type.${type}.desc`)}</CardDescription></CardHeader>
        <CardContent className="space-y-4">
          {routes.filter((route) => route.media_type === type).map((route) => <RouteRow key={route.route_key} route={route} models={query.data.models} saving={save.isPending} onSave={(next) => save.mutateAsync(next)} />)}
        </CardContent>
      </Card>)}
    </div>
  );
}

function RouteRow({ route, models, saving, onSave }: { route: MediaModelRoute; models: AIModel[]; saving: boolean; onSave: (route: MediaModelRoute) => Promise<unknown> }) {
  const { t } = useTranslation();
  const [details, setDetails] = useState(false);
  const [draft, setDraft] = useState<MediaModelRoute | null>(null);
  const modelName = (id: string | null) => models.find((model) => model.id === id)?.display_name ?? id ?? t("mediaModels.notSelected");
  return <div className="flex min-h-20 items-center justify-between gap-4 rounded-lg border p-4">
    <div className="min-w-0"><ListName onClick={() => setDetails(true)}>{t(`mediaModels.route.${route.route_key}`)}</ListName><p className="truncate text-xs text-muted-foreground">{modelName(route.primary_model_id)}</p></div>
    <div className="flex shrink-0 items-center gap-3"><Switch checked={route.enabled} disabled={saving} aria-label={t("mediaModels.enabled")} onCheckedChange={(enabled) => { void onSave({ ...route, enabled }).catch(() => {}); }} /><ListActions actions={[{ label: t("listActions.details"), onSelect: () => setDetails(true) }, { label: t("common.edit"), disabled: saving, onSelect: () => setDraft({ ...route, fallback_model_ids: [...route.fallback_model_ids] }) }]} /></div>
    {details && <ListDetails title={t(`mediaModels.route.${route.route_key}`)} onClose={() => setDetails(false)} fields={[{ label: t("mediaModels.description"), value: t(`mediaModels.route.${route.route_key}.desc`) }, { label: t("mediaModels.defaultModel"), value: modelName(route.primary_model_id) }, { label: t("mediaModels.fallbackModels"), value: route.fallback_model_ids.map(modelName).join("\n") || t("mediaModels.noFallback") }]} actions={[{ label: t("common.edit"), disabled: saving, onSelect: () => { setDetails(false); setDraft({ ...route, fallback_model_ids: [...route.fallback_model_ids] }); } }]} />}
    <Dialog open={draft !== null} onOpenChange={(open) => { if (!open && !saving) setDraft(null); }}><DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-2xl"><DialogHeader><DialogTitle>{t("common.edit")}</DialogTitle></DialogHeader>{draft && <RouteEditor route={draft} models={models} onChange={setDraft} />}<DialogFooter><Button variant="outline" disabled={saving} onClick={() => setDraft(null)}>{t("common.cancel")}</Button><Button disabled={saving || !draft} onClick={() => { if (draft) void onSave(draft).then(() => setDraft(null)).catch(() => {}); }}><Save />{t("common.save")}</Button></DialogFooter></DialogContent></Dialog>
  </div>;
}

function RouteEditor({ route, models, onChange }: { route: MediaModelRoute; models: AIModel[]; onChange: (route: MediaModelRoute) => void }) {
  const { t } = useTranslation();
  const candidates = useMemo(() => compatibleMediaModels(models, route), [models, route]);
  const selected = selectedMediaModelIDs(route);
  const modelSelect = (value: string | null, onSelect: (id: string | null) => void) => (
    <Select value={value ?? "none"} onValueChange={(v) => onSelect(v === "none" ? null : v)}>
      <SelectTrigger className="w-full"><SelectValue placeholder={t("mediaModels.notSelected")} /></SelectTrigger>
      <SelectContent>
        <SelectItem value="none">{t("mediaModels.notSelected")}</SelectItem>
        {candidates.map((model) => (
          <SelectItem key={model.id} value={model.id} disabled={model.id !== value && selected.has(model.id)}>
            {model.display_name} · {model.provider_name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
  return (
    <div className="rounded-lg border p-4">
      <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div><div className="font-medium">{t(`mediaModels.route.${route.route_key}`)}</div><div className="mt-1 text-xs text-muted-foreground">{t(`mediaModels.route.${route.route_key}.desc`)}</div></div>
        <label className="flex items-center gap-2 text-sm"><Switch checked={route.enabled} onCheckedChange={(checked) => onChange({ ...route, enabled: checked })} />{t("mediaModels.enabled")}</label>
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <div className="space-y-1.5"><label className="text-sm font-medium">{t("mediaModels.defaultModel")}</label>{modelSelect(route.primary_model_id, (id) => onChange({ ...route, primary_model_id: id }))}</div>
        <div className="space-y-2">
          <div className="flex items-center justify-between"><label className="text-sm font-medium">{t("mediaModels.fallbackModels")}</label><Button type="button" size="sm" variant="ghost" disabled={route.fallback_model_ids.length >= 5 || candidates.length <= selected.size} onClick={() => onChange({ ...route, fallback_model_ids: [...route.fallback_model_ids, ""] })}><Plus />{t("mediaModels.addFallback")}</Button></div>
          {route.fallback_model_ids.length === 0 ? <p className="text-xs text-muted-foreground">{t("mediaModels.noFallback")}</p> : route.fallback_model_ids.map((id, index) => (
            <div key={`${route.route_key}-${index}`} className="flex items-center gap-2"><span className="w-5 text-xs text-muted-foreground">{index + 1}</span><div className="flex-1">{modelSelect(id, (next) => onChange({ ...route, fallback_model_ids: route.fallback_model_ids.map((item, itemIndex) => itemIndex === index ? (next ?? "") : item).filter(Boolean) }))}</div><Button type="button" size="icon" variant="ghost" onClick={() => onChange({ ...route, fallback_model_ids: route.fallback_model_ids.filter((_, itemIndex) => itemIndex !== index) })}><Trash2 /></Button></div>
          ))}
        </div>
      </div>
      {candidates.length === 0 && <p className="mt-3 text-sm text-amber-600">{t("mediaModels.noCompatibleModels")}</p>}
      <Link to="/model-services" className="mt-3 inline-block text-xs text-muted-foreground underline">{t("mediaModels.configureEligibility")}</Link>
    </div>
  );
}
