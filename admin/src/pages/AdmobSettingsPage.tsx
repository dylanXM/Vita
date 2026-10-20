import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import { admobApi } from "@/api/admin";
import type { AdmobSettings } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { toast } from "@/components/ui/sonner";

type UnitKey = keyof Pick<AdmobSettings,
  "android_rewarded_unit_id" | "ios_rewarded_unit_id" |
  "android_banner_unit_id" | "ios_banner_unit_id" |
  "android_interstitial_unit_id" | "ios_interstitial_unit_id">;

export function AdmobSettingsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["admob-settings"], queryFn: ({ signal }) => admobApi.settings(signal) });
  const [form, setForm] = useState<AdmobSettings | null>(null);
  useEffect(() => { if (query.data) setForm(query.data); }, [query.data]);
  const save = useMutation({
    mutationFn: () => admobApi.saveSettings(form!),
    onSuccess: (data) => {
      setForm(data);
      queryClient.setQueryData(["admob-settings"], data);
      toast.success(t("admob.saved"));
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const update = <K extends keyof AdmobSettings>(key: K, value: AdmobSettings[K]) => {
    setForm((current) => current ? { ...current, [key]: value } : current);
  };
  const unitField = (key: UnitKey, label: string) =>
    <label className="space-y-2 text-sm" key={key}>
      <span>{label}</span>
      <Input value={form?.[key] ?? ""} onChange={(event) => update(key, event.target.value)} placeholder="ca-app-pub-…/…" />
    </label>;
  const toggle = (key: "rewarded_enabled" | "banner_enabled" | "interstitial_enabled" | "show_to_subscribers", label: string) =>
    <label className="flex min-h-11 items-center justify-between gap-4 border-b py-3 text-sm" key={key}>
      <span>{label}</span>
      <Switch checked={form?.[key] ?? false} onCheckedChange={(checked) => update(key, checked)} />
    </label>;

  return <div className="space-y-6">
    <PageHeader title={t("admob.title")} description={t("admob.desc")} />
    {query.isLoading || !form ? <Skeleton className="h-72 w-full" /> : <>
      <Card><CardHeader><CardTitle>{t("admob.formats")}</CardTitle></CardHeader><CardContent>
        {toggle("rewarded_enabled", t("admob.rewarded"))}
        {toggle("banner_enabled", t("admob.banner"))}
        {toggle("interstitial_enabled", t("admob.interstitial"))}
        {toggle("show_to_subscribers", t("admob.subscribers"))}
        <p className="pt-3 text-sm text-muted-foreground">{t("admob.placements")}</p>
      </CardContent></Card>
      <Card><CardHeader><CardTitle>{t("admob.rewardRules")}</CardTitle></CardHeader><CardContent className="grid gap-4 sm:grid-cols-2">
        <label className="space-y-2 text-sm"><span>{t("admob.credits")}</span><Input type="number" min={1} max={1000} value={form.reward_credits} onChange={(event) => update("reward_credits", Number(event.target.value))} /></label>
        <label className="space-y-2 text-sm"><span>{t("admob.dailyLimit")}</span><Input type="number" min={0} max={100} value={form.daily_reward_limit} onChange={(event) => update("daily_reward_limit", Number(event.target.value))} /></label>
      </CardContent></Card>
      <Card><CardHeader><CardTitle>{t("admob.units")}</CardTitle></CardHeader><CardContent className="grid gap-4 sm:grid-cols-2">
        {unitField("android_rewarded_unit_id", t("admob.androidRewarded"))}
        {unitField("ios_rewarded_unit_id", t("admob.iosRewarded"))}
        {unitField("android_banner_unit_id", t("admob.androidBanner"))}
        {unitField("ios_banner_unit_id", t("admob.iosBanner"))}
        {unitField("android_interstitial_unit_id", t("admob.androidInterstitial"))}
        {unitField("ios_interstitial_unit_id", t("admob.iosInterstitial"))}
      </CardContent></Card>
      <p className="text-sm text-muted-foreground">{t("admob.appIdHint")}</p>
      <Button disabled={save.isPending || form.reward_credits < 1 || form.reward_credits > 1000 || form.daily_reward_limit < 0 || form.daily_reward_limit > 100} onClick={() => save.mutate()}>{t("common.save")}</Button>
    </>}
  </div>;
}
