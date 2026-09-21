import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { PawPrint, Pencil, Plus, Save } from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { aiPetBreedsApi, envApi, subscriptionPlansApi } from "@/api/admin";
import type { AIPetBreed, AIPetBreedInput, Environment } from "@/api/types";
import { ENVIRONMENTS } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const emptyForm = (environment: Environment): AIPetBreedInput => ({
  environment,
  name: "",
  species: "",
  personality: "",
  description: "",
  avatar_url: "",
  sort_order: 0,
  enabled: true,
  subscription_plan_ids: [],
});

function Field({ label, children, wide = false }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return <div className={`space-y-1.5 ${wide ? "md:col-span-2" : ""}`}><Label>{label}</Label>{children}</div>;
}

export function AIPetsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const envQuery = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const activeEnv = environment ?? envQuery.data?.environment;
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState<AIPetBreedInput>(emptyForm("dev"));

  useEffect(() => {
    if (!environment && envQuery.data?.environment) setEnvironment(envQuery.data.environment);
  }, [environment, envQuery.data]);
  useEffect(() => {
    if (activeEnv && !editing) setForm(emptyForm(activeEnv));
  }, [activeEnv, editing]);

  const breeds = useQuery({
    queryKey: ["ai-pet-breeds", activeEnv],
    queryFn: ({ signal }) => aiPetBreedsApi.list(activeEnv!, signal),
    enabled: Boolean(activeEnv),
  });
  const plans = useQuery({
    queryKey: ["subscription-plans", activeEnv],
    queryFn: ({ signal }) => subscriptionPlansApi.list({ environment: activeEnv! }, signal),
    enabled: Boolean(activeEnv),
  });
  const reset = () => {
    setEditing(null);
    if (activeEnv) setForm(emptyForm(activeEnv));
  };
  const save = useMutation({
    mutationFn: () => editing ? aiPetBreedsApi.update(editing, form) : aiPetBreedsApi.create(form),
    onSuccess: () => {
      toast.success(t("aiPets.saved"));
      reset();
      void queryClient.invalidateQueries({ queryKey: ["ai-pet-breeds"] });
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const edit = (breed: AIPetBreed) => {
    setEditing(breed.id);
    setForm({
      environment: breed.environment,
      name: breed.name,
      species: breed.species,
      personality: breed.personality,
      description: breed.description,
      avatar_url: breed.avatar_url,
      sort_order: breed.sort_order,
      enabled: breed.enabled,
      subscription_plan_ids: breed.subscription_plan_ids ?? [],
    });
  };

  return <div className="space-y-6">
    <PageHeader title={t("aiPets.title")} description={t("aiPets.desc")} actions={
      <Select value={activeEnv ?? ""} onValueChange={(value) => { setEnvironment(value as Environment); setEditing(null); }}>
        <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
        <SelectContent>{ENVIRONMENTS.map((env) => <SelectItem key={env} value={env}>{t(`billing.env.${env}`)}</SelectItem>)}</SelectContent>
      </Select>
    } />
    <Card>
      <CardHeader><CardTitle>{editing ? t("aiPets.edit") : t("aiPets.create")}</CardTitle><CardDescription>{t("aiPets.formDesc")}</CardDescription></CardHeader>
      <CardContent className="space-y-5">
        <div className="grid gap-4 md:grid-cols-2">
          <Field label={t("aiPets.name")}><Input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} /></Field>
          <Field label={t("aiPets.species")}><Input value={form.species} onChange={(event) => setForm({ ...form, species: event.target.value })} /></Field>
          <Field label={t("aiPets.personality")}><Input value={form.personality} onChange={(event) => setForm({ ...form, personality: event.target.value })} placeholder={t("aiPets.personalityHint")} /></Field>
          <Field label={t("aiPets.avatarUrl")}><Input value={form.avatar_url} onChange={(event) => setForm({ ...form, avatar_url: event.target.value })} placeholder="https://…" /></Field>
          <Field wide label={t("aiPets.description")}><textarea className="min-h-24 w-full rounded-md border bg-background p-3 text-sm" value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} /></Field>
          <Field label={t("aiPets.sortOrder")}><Input type="number" value={form.sort_order} onChange={(event) => setForm({ ...form, sort_order: Number(event.target.value) || 0 })} /></Field>
          <div className="flex items-end"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.enabled} onChange={(event) => setForm({ ...form, enabled: event.target.checked })} />{t("content.enabled")}</label></div>
        </div>
        <div className="rounded-md border p-4">
          <div className="font-medium">{t("aiPets.subscriptionAccess")}</div>
          <p className="mt-1 text-xs text-muted-foreground">{t("aiPets.subscriptionAccessDesc")}</p>
          <div className="mt-3 grid max-h-52 gap-2 overflow-y-auto md:grid-cols-2">
            {(plans.data?.items ?? []).map((plan) => <label key={plan.id} className="flex items-start gap-2 text-sm"><input type="checkbox" className="mt-1" checked={form.subscription_plan_ids.includes(plan.id)} onChange={(event) => setForm({ ...form, subscription_plan_ids: event.target.checked ? [...form.subscription_plan_ids, plan.id] : form.subscription_plan_ids.filter((id) => id !== plan.id) })} /><span>{plan.name}<span className="block text-xs text-muted-foreground">{t(`billing.platform.${plan.platform}`)} · {plan.product_id}</span></span></label>)}
          </div>
        </div>
        <div className="flex gap-2"><Button disabled={!activeEnv || !form.name.trim() || !form.species.trim() || save.isPending} onClick={() => save.mutate()}>{editing ? <Save /> : <Plus />}{editing ? t("aiPets.update") : t("aiPets.add")}</Button>{editing && <Button variant="outline" onClick={reset}>{t("users.cancel")}</Button>}</div>
      </CardContent>
    </Card>
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {(breeds.data?.items ?? []).map((breed) => <Card key={breed.id}>
        <CardContent className="flex gap-4 p-4">
          <div className="grid size-20 shrink-0 place-items-center overflow-hidden rounded-xl bg-muted">{breed.avatar_url ? <img src={breed.avatar_url} alt="" className="size-full object-cover" /> : <PawPrint className="size-8 text-muted-foreground" />}</div>
          <div className="min-w-0 flex-1"><div className="flex items-center gap-2"><div className="font-semibold">{breed.name}</div><Badge variant={breed.enabled ? "success" : "outline"}>{breed.enabled ? t("content.enabled") : t("content.disabled")}</Badge></div><div className="text-sm text-muted-foreground">{breed.species}</div><p className="mt-2 line-clamp-2 text-sm">{breed.description}</p><div className="mt-3 flex items-center justify-between text-xs text-muted-foreground"><span>{breed.subscription_plan_ids.length ? t("aiPets.selectedPlans", { count: breed.subscription_plan_ids.length }) : t("aiPets.allPlans")}</span><Button size="sm" variant="outline" onClick={() => edit(breed)}><Pencil />{t("users.edit")}</Button></div></div>
        </CardContent>
      </Card>)}
    </div>
  </div>;
}
