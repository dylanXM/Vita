import { useEffect, useState } from "react";
import { Switch } from "@/components/ui/switch";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { usersApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { ContactPreferences } from "@/api/types";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/sonner";

export function UserContactPreferences({ userID }: { userID: string }) {
  const { t } = useTranslation();
  const query = useQuery({ queryKey: ["user-contact-preferences", userID], queryFn: ({ signal }) => usersApi.contactPreferences(userID, signal) });
  const [form, setForm] = useState<ContactPreferences | null>(null);
  useEffect(() => { if (query.data) setForm(query.data.preferences); }, [query.data]);
  const save = useMutation({
    mutationFn: (values: ContactPreferences) => usersApi.saveContactPreferences(userID, values),
    onSuccess: (data) => { setForm(data.preferences); void query.refetch(); toast.success(t("contact.saved")); },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const valid = form && Number.isInteger(form.daily_limit) && form.daily_limit >= 0 && form.daily_limit <= 8
    && Number.isInteger(form.minimum_gap_minutes) && form.minimum_gap_minutes >= 30 && form.minimum_gap_minutes <= 1440
    && Number.isInteger(form.quiet_start) && form.quiet_start >= 0 && form.quiet_start <= 23
    && Number.isInteger(form.quiet_end) && form.quiet_end >= 0 && form.quiet_end <= 23
    && (!form.quiet_enabled || form.quiet_start !== form.quiet_end);
  return <Card>
    <CardHeader><CardTitle>{t("contact.title")}</CardTitle></CardHeader>
    <CardContent className="space-y-4">
      <p className="text-sm text-muted-foreground">{t("contact.hint")}</p>
      {query.isError ? <Button variant="outline" onClick={() => void query.refetch()}>{t("common.refresh")}</Button> : !form ? <p>{t("common.loading")}</p> : <>
        <p className="text-sm text-muted-foreground">{t("users.timezone")}: {query.data?.timezone}</p>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="space-y-2 text-sm">{t("contact.dailyLimit")}<Input type="number" min={0} max={8} value={form.daily_limit} disabled={save.isPending} onChange={(e) => setForm({ ...form, daily_limit: e.target.valueAsNumber })} /></label>
          <label className="space-y-2 text-sm">{t("contact.gap")}<Input type="number" min={30} max={1440} value={form.minimum_gap_minutes} disabled={save.isPending} onChange={(e) => setForm({ ...form, minimum_gap_minutes: e.target.valueAsNumber })} /></label>
        </div>
        <label className="flex items-center gap-2 text-sm"><Switch checked={form.quiet_enabled} disabled={save.isPending} onCheckedChange={(checked) => setForm({ ...form, quiet_enabled: checked })} />{t("contact.quiet")}</label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="space-y-2 text-sm">{t("contact.start")}<Input type="number" min={0} max={23} value={form.quiet_start} disabled={!form.quiet_enabled || save.isPending} onChange={(e) => setForm({ ...form, quiet_start: e.target.valueAsNumber })} /></label>
          <label className="space-y-2 text-sm">{t("contact.end")}<Input type="number" min={0} max={23} value={form.quiet_end} disabled={!form.quiet_enabled || save.isPending} onChange={(e) => setForm({ ...form, quiet_end: e.target.valueAsNumber })} /></label>
        </div>
        <Button disabled={!valid || save.isPending} onClick={() => save.mutate(form)}>{t("common.save")}</Button>
      </>}
    </CardContent>
  </Card>;
}
