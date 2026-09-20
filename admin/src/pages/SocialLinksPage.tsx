import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { envApi, socialLinksApi } from "@/api/admin";
import type { Environment } from "@/api/types";
import { ENVIRONMENTS } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";

export function SocialLinksPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const serverEnv = useQuery({
    queryKey: ["admin-environment"],
    queryFn: ({ signal }) => envApi.get(signal),
  });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const activeEnv = environment ?? serverEnv.data?.environment;
  const query = useQuery({
    queryKey: ["social-links", activeEnv],
    queryFn: ({ signal }) => socialLinksApi.get(activeEnv!, signal),
    enabled: Boolean(activeEnv),
  });

  const [instagram, setInstagram] = useState("");
  const [tiktok, setTiktok] = useState("");
  const [xUrl, setXUrl] = useState("");
  const [discord, setDiscord] = useState("");

  useEffect(() => {
    if (!query.data) return;
    setInstagram(query.data.social_instagram_url);
    setTiktok(query.data.social_tiktok_url);
    setXUrl(query.data.social_x_url);
    setDiscord(query.data.social_discord_url);
  }, [query.data]);

  const save = useMutation({
    mutationFn: () => socialLinksApi.save(activeEnv!, {
      social_instagram_url: instagram.trim(),
      social_tiktok_url: tiktok.trim(),
      social_x_url: xUrl.trim(),
      social_discord_url: discord.trim(),
    }),
    onSuccess: (data) => {
      queryClient.setQueryData(["social-links", activeEnv], data);
      toast.success(t("social.saved"));
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("social.title")}
        description={t("social.desc")}
        actions={
          <Select value={activeEnv ?? ""} onValueChange={(value) => setEnvironment(value as Environment)}>
            <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
            <SelectContent>
              {ENVIRONMENTS.map((value) => <SelectItem key={value} value={value}>{value}</SelectItem>)}
            </SelectContent>
          </Select>
        }
      />
      <Card>
        <CardHeader>
          <CardTitle>{t("social.cardTitle")}</CardTitle>
          <CardDescription>{t("social.cardDesc")}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {query.isLoading ? <Skeleton className="h-52 w-full" /> : <>
            <URLField id="instagram-url" label="Instagram" value={instagram} placeholder="https://www.instagram.com/…" onChange={setInstagram} />
            <URLField id="tiktok-url" label="TikTok" value={tiktok} placeholder="https://www.tiktok.com/@…" onChange={setTiktok} />
            <URLField id="x-url" label="X" value={xUrl} placeholder="https://x.com/…" onChange={setXUrl} />
            <URLField id="discord-url" label="Discord" value={discord} placeholder="https://discord.gg/…" onChange={setDiscord} />
            <p className="text-xs text-muted-foreground">{t("social.hint")}</p>
            <div className="flex justify-end">
              <Button disabled={!activeEnv || save.isPending} onClick={() => save.mutate()}>
                {t("social.save")}
              </Button>
            </div>
          </>}
        </CardContent>
      </Card>
    </div>
  );
}

function URLField({ id, label, value, placeholder, onChange }: {
  id: string;
  label: string;
  value: string;
  placeholder: string;
  onChange: (value: string) => void;
}) {
  return <div className="space-y-2">
    <Label htmlFor={id}>{label}</Label>
    <Input id={id} type="url" inputMode="url" value={value} placeholder={placeholder} onChange={(event) => onChange(event.target.value)} />
  </div>;
}
