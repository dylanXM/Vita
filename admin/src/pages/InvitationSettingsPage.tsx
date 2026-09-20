import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Coins, Save, Users } from "lucide-react";
import { useTranslation } from "react-i18next";

import { invitationApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";

export function InvitationSettingsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const settings = useQuery({
    queryKey: ["invitation-settings"],
    queryFn: ({ signal }) => invitationApi.settings(signal),
  });
  const [percent, setPercent] = useState(0);
  useEffect(() => {
    if (settings.data) setPercent(settings.data.reward_percent);
  }, [settings.data]);
  const save = useMutation({
    mutationFn: () => invitationApi.saveSettings(percent),
    onSuccess: (data) => {
      queryClient.setQueryData(["invitation-settings"], data);
      toast.success(t("invitation.saved"));
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });

  return <div className="space-y-6">
    <PageHeader title={t("invitation.title")} description={t("invitation.desc")} />
    {settings.isLoading ? <Skeleton className="h-36 w-full" /> : <>
      <div className="grid gap-4 sm:grid-cols-2">
        <StatCard label={t("invitation.invitedUsers")} value={settings.data?.invited_users ?? 0} icon={Users} />
        <StatCard label={t("invitation.rewardedCoins")} value={settings.data?.rewarded_coins ?? 0} icon={Coins} />
      </div>
      <Card>
        <CardHeader><CardTitle>{t("invitation.rate")}</CardTitle><CardDescription>{t("invitation.rateDesc")}</CardDescription></CardHeader>
        <CardContent className="space-y-4">
          <label className="block max-w-sm space-y-2 text-sm"><span>{t("invitation.percent")}</span><Input type="number" min={0} max={100} step={0.01} value={percent} onChange={(event) => setPercent(Number(event.target.value))} /></label>
          <p className="text-sm text-muted-foreground">{t("invitation.example", { coins: Math.floor(1000 * percent / 100) })}</p>
          <Button disabled={percent < 0 || percent > 100 || save.isPending} onClick={() => save.mutate()}><Save />{t("invitation.save")}</Button>
        </CardContent>
      </Card>
    </>}
  </div>;
}
