import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Headphones, Image, Plus, Save, Trash2, Video } from "lucide-react";
import { useTranslation } from "react-i18next";

import { agentApi } from "@/api/admin";
import type { AIModel, MediaModelRoute, MediaModelType } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";

const groups: Array<{ type: MediaModelType; icon: typeof Image }> = [
  { type: "image", icon: Image },
  { type: "audio", icon: Headphones },
  { type: "video", icon: Video },
];

export function MediaModelsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["media-model-routes"], queryFn: ({ signal }) => agentApi.mediaRoutes(signal) });
  const [routes, setRoutes] = useState<MediaModelRoute[]>([]);
  useEffect(() => { if (query.data) setRoutes(query.data.routes); }, [query.data]);
  const save = useMutation({
    mutationFn: () => agentApi.saveMediaRoutes(routes),
    onSuccess: (data) => {
      setRoutes(data.routes);
      toast.success(t("mediaModels.saved"));
      void queryClient.invalidateQueries({ queryKey: ["agent-config"] });
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  if (query.isLoading) return <Skeleton className="h-96" />;
  if (!query.data || query.isError) return <p className="text-sm text-destructive">{t("common.failedToLoad")}</p>;
  const update = (next: MediaModelRoute) => setRoutes((items) => items.map((item) => item.route_key === next.route_key ? next : item));
  return (
    <div className="space-y-6">
      <PageHeader title={t("mediaModels.title")} description={t("mediaModels.description")} actions={<Button disabled={save.isPending} onClick={() => save.mutate()}><Save />{t("mediaModels.save")}</Button>} />
      {groups.map(({ type, icon: Icon }) => (
        <Card key={type}>
          <CardHeader><CardTitle className="flex items-center gap-2"><Icon className="size-5" />{t(`mediaModels.type.${type}`)}</CardTitle><CardDescription>{t(`mediaModels.type.${type}.desc`)}</CardDescription></CardHeader>
          <CardContent className="space-y-4">
            {routes.filter((route) => route.media_type === type).map((route) => (
              <RouteEditor key={route.route_key} route={route} models={query.data.models} onChange={update} />
            ))}
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

function RouteEditor({ route, models, onChange }: { route: MediaModelRoute; models: AIModel[]; onChange: (route: MediaModelRoute) => void }) {
  const { t } = useTranslation();
  const candidates = useMemo(() => models.filter((model) => model.enabled && model.capabilities.includes(route.media_type)), [models, route.media_type]);
  const selected = new Set([route.primary_model_id, ...route.fallback_model_ids].filter(Boolean));
  const modelSelect = (value: string | null, onSelect: (id: string | null) => void) => (
    <select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={value ?? ""} onChange={(event) => onSelect(event.target.value || null)}>
      <option value="">{t("mediaModels.notSelected")}</option>
      {candidates.map((model) => <option key={model.id} value={model.id} disabled={model.id !== value && selected.has(model.id)}>{model.display_name} · {model.provider_name}</option>)}
    </select>
  );
  return (
    <div className="rounded-lg border p-4">
      <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div><div className="font-medium">{t(`mediaModels.route.${route.route_key}`)}</div><div className="mt-1 text-xs text-muted-foreground">{t(`mediaModels.route.${route.route_key}.desc`)}</div></div>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={route.enabled} onChange={(event) => onChange({ ...route, enabled: event.target.checked })} />{t("mediaModels.enabled")}</label>
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
    </div>
  );
}
