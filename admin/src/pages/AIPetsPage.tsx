import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { PawPrint, Pencil, Plus, Save } from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { aiPetBreedsApi, subscriptionPlansApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { AIPetBreed, AIPetBreedInput, Environment } from "@/api/types";
import { ConfigurationButton } from "@/components/configuration-button";
import { AdminImageInput, isAdminImageURL } from "@/components/admin-image-input";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

const emptyForm = (environment: Environment): AIPetBreedInput => ({
  environment, name: "", species: "", personality: "", description: "", avatar_url: "",
  sort_order: 0, enabled: true, subscription_plan_ids: [],
});

function Field({ label, children, wide = false }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return <div className={`space-y-1.5 ${wide ? "md:col-span-2" : ""}`}><Label>{label}</Label>{children}</div>;
}

export function AIPetsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const activeEnv: Environment = "prod";
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState<AIPetBreedInput>(emptyForm("prod"));
  const [imageUploading, setImageUploading] = useState(false);


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
  const close = () => { setOpen(false); setEditing(null); };
  const save = useMutation({
    mutationFn: () => editing ? aiPetBreedsApi.update(editing, form) : aiPetBreedsApi.create(form),
    onSuccess: () => {
      toast.success(t("aiPets.saved"));
      close();
      void queryClient.invalidateQueries({ queryKey: ["ai-pet-breeds", activeEnv] });
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const create = () => {
    if (!activeEnv) return;
    setEditing(null);
    setForm(emptyForm(activeEnv));
    setOpen(true);
  };
  const edit = (breed: AIPetBreed) => {
    setEditing(breed.id);
    setForm({
      environment: "prod", name: breed.name, species: breed.species,
      personality: breed.personality, description: breed.description,
      avatar_url: breed.avatar_url, sort_order: breed.sort_order,
      enabled: breed.enabled, subscription_plan_ids: [...(breed.subscription_plan_ids ?? [])],
    });
    setOpen(true);
  };

  return <div className="space-y-6">
    <PageHeader title={t("aiPets.title")} description={t("aiPets.desc")} actions={<>
      <ConfigurationButton label={t("aiPets.create")} icon={<Plus />} onClick={create} disabled={!activeEnv}
        details={breeds.data ? [`${t("aiPets.configuredCount")}: ${breeds.data.items.length}`, ...breeds.data.items.map((breed) => breed.name)] : [t(breeds.isError ? "common.failedToLoad" : "common.loading")]} />
    </>} />
    <Card><CardContent className="p-4">
      {breeds.isError ? <p className="py-8 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
        : breeds.isLoading ? <p className="py-8 text-center text-sm text-muted-foreground">{t("common.loading")}</p>
        : !breeds.data?.items.length ? <p className="py-8 text-center text-sm text-muted-foreground">{t("aiPets.empty")}</p>
        : <Table><TableHeader><TableRow>
          <TableHead>{t("aiPets.name")}</TableHead><TableHead>{t("aiPets.species")}</TableHead>
          <TableHead>{t("aiPets.subscriptionAccess")}</TableHead><TableHead>{t("content.enabled")}</TableHead>
          <TableHead className="text-end">{t("users.actions")}</TableHead>
        </TableRow></TableHeader><TableBody>{breeds.data.items.map((breed) => <TableRow key={breed.id}>
          <TableCell><div className="flex items-center gap-3">
            <div className="grid size-12 shrink-0 place-items-center overflow-hidden rounded-lg bg-muted">
              {breed.avatar_url && !breed.avatar_url.startsWith("asset://") ? <img src={breed.avatar_url} alt="" className="size-full object-cover" /> : <PawPrint className="size-5 text-muted-foreground" />}
            </div><div><div className="font-medium">{breed.name}</div><div className="line-clamp-1 max-w-72 text-xs text-muted-foreground">{breed.description}</div></div>
          </div></TableCell>
          <TableCell>{breed.species}</TableCell>
          <TableCell>{breed.subscription_plan_ids.length ? t("aiPets.selectedPlans", { count: breed.subscription_plan_ids.length }) : t("aiPets.allPlans")}</TableCell>
          <TableCell><Badge variant={breed.enabled ? "success" : "outline"}>{t(breed.enabled ? "content.enabled" : "content.disabled")}</Badge></TableCell>
          <TableCell className="text-end"><ConfigurationButton label={t("users.edit")} icon={<Pencil />} onClick={() => edit(breed)}
            details={[
              `${t("aiPets.name")}: ${breed.name}`,
              `${t("aiPets.species")}: ${breed.species}`,
              `${t("aiPets.personality")}: ${breed.personality || "—"}`,
              `${t("aiPets.description")}: ${breed.description || "—"}`,
              `${t("aiPets.avatarUrl")}: ${breed.avatar_url || "—"}`,
              `${t("aiPets.subscriptionAccess")}: ${breed.subscription_plan_ids.length ? breed.subscription_plan_ids.map((id) => plans.data?.items.find((plan) => plan.id === id)?.name ?? id).join(", ") : t("aiPets.allPlans")}`,
              `${t("aiPets.sortOrder")}: ${breed.sort_order}`,
              `${t("content.enabled")}: ${t(breed.enabled ? "content.enabled" : "content.disabled")}`,
            ]} /></TableCell>
        </TableRow>)}</TableBody></Table>}
    </CardContent></Card>
    <Dialog open={open} onOpenChange={(next) => { if (!next) close(); }}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader><DialogTitle>{editing ? t("aiPets.edit") : t("aiPets.create")}</DialogTitle><DialogDescription>{t("aiPets.formDesc")}</DialogDescription></DialogHeader>
        <div className="space-y-5">
          <div className="grid gap-4 md:grid-cols-2">
            <Field label={t("aiPets.name")}><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
            <Field label={t("aiPets.species")}><Input value={form.species} onChange={(e) => setForm({ ...form, species: e.target.value })} /></Field>
            <Field label={t("aiPets.personality")}><Input value={form.personality} onChange={(e) => setForm({ ...form, personality: e.target.value })} placeholder={t("aiPets.personalityHint")} /></Field>
            <Field label={t("aiPets.avatarUrl")}><AdminImageInput value={form.avatar_url} onChange={(url) => setForm((current) => ({ ...current, avatar_url: url }))} onUploadingChange={setImageUploading} /></Field>
            <Field wide label={t("aiPets.description")}><textarea className="min-h-24 w-full rounded-md border bg-background p-3 text-sm" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} /></Field>
            <Field label={t("aiPets.sortOrder")}><Input type="number" value={form.sort_order} onChange={(e) => setForm({ ...form, sort_order: Number(e.target.value) || 0 })} /></Field>
            <div className="flex items-end"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.enabled} onChange={(e) => setForm({ ...form, enabled: e.target.checked })} />{t("content.enabled")}</label></div>
          </div>
          <div className="rounded-md border p-4"><div className="font-medium">{t("aiPets.subscriptionAccess")}</div><p className="mt-1 text-xs text-muted-foreground">{t("aiPets.subscriptionAccessDesc")}</p>
            <div className="mt-3 grid max-h-52 gap-2 overflow-y-auto md:grid-cols-2">
              {(plans.data?.items ?? []).map((plan) => <label key={plan.id} className="flex items-start gap-2 text-sm"><input type="checkbox" className="mt-1" checked={form.subscription_plan_ids.includes(plan.id)} onChange={(event) => setForm({ ...form, subscription_plan_ids: event.target.checked ? [...form.subscription_plan_ids, plan.id] : form.subscription_plan_ids.filter((id) => id !== plan.id) })} /><span>{plan.name}<span className="block text-xs text-muted-foreground">{t(`billing.platform.${plan.platform}`)} · {plan.product_id}</span></span></label>)}
            </div>
          </div>
        </div>
        <DialogFooter><Button variant="outline" onClick={close}>{t("users.cancel")}</Button><Button disabled={!activeEnv || !form.name.trim() || !form.species.trim() || !isAdminImageURL(form.avatar_url.trim()) || imageUploading || save.isPending} onClick={() => save.mutate()}>{editing ? <Save /> : <Plus />}{editing ? t("aiPets.update") : t("aiPets.add")}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </div>;
}
