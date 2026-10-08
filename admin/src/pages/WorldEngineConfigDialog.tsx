import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { type WorldCampaign, type WorldCampaignInput, type WorldPlace, worldEngineApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const kinds = ["home", "work", "cafe", "outdoors", "story"] as const;

const emptyCampaign: WorldCampaignInput = {
  region_code: "global", title: "", description: "", scene_kind: "home", ambience: "clear",
  starts_on: "", ends_on: "", priority: 0, enabled: false,
};

export function WorldEngineConfigDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<"places" | "campaigns">("places");
  const [place, setPlace] = useState<WorldPlace | null>(null);
  const [campaignId, setCampaignId] = useState<string | null>(null);
  const [campaign, setCampaign] = useState<WorldCampaignInput | null>(null);
  const places = useQuery({ queryKey: ["world-engine-places"], queryFn: ({ signal }) => worldEngineApi.places(signal), enabled: open });
  const campaigns = useQuery({ queryKey: ["world-engine-campaigns"], queryFn: ({ signal }) => worldEngineApi.campaigns(signal), enabled: open });
  const refresh = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["world-engine-places"] }),
      queryClient.invalidateQueries({ queryKey: ["world-engine-campaigns"] }),
    ]);
  };
  const savePlace = useMutation({
    mutationFn: (item: WorldPlace) => worldEngineApi.savePlace(item.scene_kind, item),
    onSuccess: () => { toast.success(t("worldEngine.saved")); setPlace(null); void refresh(); },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const saveCampaign = useMutation({
    mutationFn: ({ id, body }: { id: string | null; body: WorldCampaignInput }) =>
      id ? worldEngineApi.updateCampaign(id, body) : worldEngineApi.createCampaign(body),
    onSuccess: () => { toast.success(t("worldEngine.saved")); setCampaign(null); setCampaignId(null); void refresh(); },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const deleteCampaign = useMutation({
    mutationFn: worldEngineApi.deleteCampaign,
    onSuccess: () => { toast.success(t("worldEngine.deleted")); void refresh(); },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return <Dialog open={open} onOpenChange={onOpenChange}>
    <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
      <DialogHeader>
        <DialogTitle>{t("worldEngine.config")}</DialogTitle>
        <DialogDescription>{t("worldEngine.configHint")}</DialogDescription>
      </DialogHeader>
      <div className="flex gap-2">
        <Button variant={tab === "places" ? "default" : "outline"} onClick={() => { setTab("places"); setCampaign(null); }}>{t("worldEngine.places")}</Button>
        <Button variant={tab === "campaigns" ? "default" : "outline"} onClick={() => { setTab("campaigns"); setPlace(null); }}>{t("worldEngine.campaigns")}</Button>
      </div>
      {tab === "places" && <div className="space-y-3">
        {(places.data?.items ?? []).map((item) => <div key={item.scene_kind} className="flex items-start justify-between gap-3 rounded-xl border p-3">
          <div>
            <div className="font-medium">{t(`worldEngine.kind.${item.scene_kind}`)} · {item.title}</div>
            <div className="text-sm text-muted-foreground">{item.description}</div>
            <div className="text-xs text-muted-foreground">{item.enabled ? t("worldEngine.enabled") : t("worldEngine.disabled")}</div>
          </div>
          <Button variant="outline" size="sm" onClick={() => setPlace({ ...item })}>{t("common.edit")}</Button>
        </div>)}
        {place && <form className="space-y-3 rounded-xl border p-4" onSubmit={(event) => { event.preventDefault(); savePlace.mutate(place); }}>
          <div className="font-semibold">{t(`worldEngine.kind.${place.scene_kind}`)}</div>
          <div><Label htmlFor="world-place-title">{t("worldEngine.title")}</Label><Input id="world-place-title" value={place.title} maxLength={80} required onChange={(event) => setPlace({ ...place, title: event.target.value })} /></div>
          <div><Label htmlFor="world-place-description">{t("worldEngine.description")}</Label><Input id="world-place-description" value={place.description} maxLength={300} onChange={(event) => setPlace({ ...place, description: event.target.value })} /></div>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={place.enabled} onChange={(event) => setPlace({ ...place, enabled: event.target.checked })} />{t("worldEngine.enabled")}</label>
          <div className="flex gap-2"><Button type="submit" disabled={savePlace.isPending}>{t("common.save")}</Button><Button type="button" variant="outline" onClick={() => setPlace(null)}>{t("common.cancel")}</Button></div>
        </form>}
      </div>}
      {tab === "campaigns" && <div className="space-y-3">
        <Button variant="outline" onClick={() => { setCampaign({ ...emptyCampaign }); setCampaignId(null); }}>{t("worldEngine.newCampaign")}</Button>
        {(campaigns.data?.items ?? []).map((item: WorldCampaign) => <div key={item.id} className="flex items-start justify-between gap-3 rounded-xl border p-3">
          <div>
            <div className="font-medium">{item.title} · {item.region_code}</div>
            <div className="text-sm text-muted-foreground">{item.starts_on} — {item.ends_on} · {t(`worldEngine.kind.${item.scene_kind}`)} · {t(`worldEngine.weather.${item.ambience}`)}</div>
            <div className="text-xs text-muted-foreground">{item.enabled ? t("worldEngine.enabled") : t("worldEngine.disabled")}</div>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => { setCampaignId(item.id); setCampaign({ region_code: item.region_code, title: item.title, description: item.description, scene_kind: item.scene_kind, ambience: item.ambience, starts_on: item.starts_on, ends_on: item.ends_on, priority: item.priority, enabled: item.enabled }); }}>{t("common.edit")}</Button>
            <Button variant="outline" size="sm" disabled={deleteCampaign.isPending} onClick={() => { if (window.confirm(t("worldEngine.deleteConfirm"))) deleteCampaign.mutate(item.id); }}>{t("common.delete")}</Button>
          </div>
        </div>)}
        {campaign && <form className="space-y-3 rounded-xl border p-4" onSubmit={(event) => { event.preventDefault(); saveCampaign.mutate({ id: campaignId, body: campaign }); }}>
          <div className="font-semibold">{campaignId ? t("worldEngine.editCampaign") : t("worldEngine.newCampaign")}</div>
          <div><Label htmlFor="world-campaign-title">{t("worldEngine.title")}</Label><Input id="world-campaign-title" value={campaign.title} maxLength={100} required onChange={(event) => setCampaign({ ...campaign, title: event.target.value })} /></div>
          <div><Label htmlFor="world-campaign-description">{t("worldEngine.description")}</Label><Input id="world-campaign-description" value={campaign.description} maxLength={500} onChange={(event) => setCampaign({ ...campaign, description: event.target.value })} /></div>
          <div><Label htmlFor="world-campaign-region">{t("worldEngine.region")}</Label><Input id="world-campaign-region" value={campaign.region_code} maxLength={6} required placeholder="global / CN / US" onChange={(event) => setCampaign({ ...campaign, region_code: event.target.value })} /></div>
          <div><Label htmlFor="world-campaign-kind">{t("worldEngine.place")}</Label><select id="world-campaign-kind" className="w-full rounded-md border bg-background p-2" value={campaign.scene_kind} onChange={(event) => setCampaign({ ...campaign, scene_kind: event.target.value })}>{kinds.map((kind) => <option key={kind} value={kind}>{t(`worldEngine.kind.${kind}`)}</option>)}</select></div>
          <div><Label htmlFor="world-campaign-weather">{t("worldEngine.ambience")}</Label><select id="world-campaign-weather" className="w-full rounded-md border bg-background p-2" value={campaign.ambience} onChange={(event) => setCampaign({ ...campaign, ambience: event.target.value as WorldCampaignInput["ambience"] })}>{(["clear", "rain", "snow"] as const).map((weather) => <option key={weather} value={weather}>{t(`worldEngine.weather.${weather}`)}</option>)}</select></div>
          <div className="grid grid-cols-2 gap-3"><div><Label htmlFor="world-campaign-start">{t("worldEngine.startsOn")}</Label><Input id="world-campaign-start" type="date" value={campaign.starts_on} required onChange={(event) => setCampaign({ ...campaign, starts_on: event.target.value })} /></div><div><Label htmlFor="world-campaign-end">{t("worldEngine.endsOn")}</Label><Input id="world-campaign-end" type="date" value={campaign.ends_on} required onChange={(event) => setCampaign({ ...campaign, ends_on: event.target.value })} /></div></div>
          <div><Label htmlFor="world-campaign-priority">{t("worldEngine.priority")}</Label><Input id="world-campaign-priority" type="number" min={-1000} max={1000} value={campaign.priority} onChange={(event) => setCampaign({ ...campaign, priority: Number(event.target.value) })} /></div>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={campaign.enabled} onChange={(event) => setCampaign({ ...campaign, enabled: event.target.checked })} />{t("worldEngine.enabled")}</label>
          <div className="flex gap-2"><Button type="submit" disabled={saveCampaign.isPending}>{t("common.save")}</Button><Button type="button" variant="outline" onClick={() => { setCampaign(null); setCampaignId(null); }}>{t("common.cancel")}</Button></div>
        </form>}
      </div>}
    </DialogContent>
  </Dialog>;
}
