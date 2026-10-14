import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { creditProductsApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { CreditProduct } from "@/api/types";
import { PageHeader } from "@/components/page-header";
import { ListActions, ListName } from "@/components/list-actions";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

export function CreditProductsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const environment = "prod" as const;
  const [dialog, setDialog] = useState<{ product: CreditProduct; editing: boolean } | null>(null);
  const [draft, setDraft] = useState<CreditProduct | null>(null);
  const [coins, setCoins] = useState("");
  const products = useQuery({ queryKey: ["credit-products", environment], queryFn: ({ signal }) => creditProductsApi.list(environment, signal) });
  const save = useMutation({
    mutationFn: (product: CreditProduct) => creditProductsApi.update(environment, product.key, product),
    onSuccess: () => {
      toast.success(t("creditProducts.saved"));
      setDialog(null);
      setDraft(null);
      void queryClient.invalidateQueries({ queryKey: ["credit-products", environment] });
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const open = (product: CreditProduct, editing: boolean) => {
    setDialog({ product, editing });
    setDraft({ ...product, scene_background_url: String(product.metadata?.scene_background_url ?? ""), scene_audio_url: String(product.metadata?.scene_audio_url ?? "") });
    setCoins(String(product.coins));
  };
  const name = (product: CreditProduct) => product.key === "date_dance" ? t("creditProducts.ballroom") : t(product.name_key, { defaultValue: product.key });
  const editable = dialog?.editing === true && !save.isPending;
  const validCoins = coins.trim() !== "" && Number.isInteger(Number(coins)) && Number(coins) >= 1 && Number(coins) <= 100000;
  const changed = !!dialog && !!draft && (Number(coins) !== dialog.product.coins || draft.enabled !== dialog.product.enabled || draft.subscription_only !== dialog.product.subscription_only || draft.is_launched !== dialog.product.is_launched || draft.scene_background_url !== String(dialog.product.metadata?.scene_background_url ?? "") || draft.scene_audio_url !== String(dialog.product.metadata?.scene_audio_url ?? ""));
  const close = () => { if (!save.isPending) { setDialog(null); setDraft(null); } };

  return <div className="space-y-6">
    <PageHeader title={t("creditProducts.title")} description={t("creditProducts.description")} />
    <div className="overflow-hidden rounded-lg border bg-card"><Table>
      <TableHeader><TableRow>
        <TableHead>{t("creditProducts.product")}</TableHead><TableHead>{t("creditProducts.category")}</TableHead><TableHead>{t("creditProducts.coins")}</TableHead>
        <TableHead>{t("creditProducts.enabled")}</TableHead><TableHead>{t("creditProducts.subscriptionOnly")}</TableHead><TableHead>{t("creditProducts.isLaunched")}</TableHead><TableHead className="text-end">{t("users.actions")}</TableHead>
      </TableRow></TableHeader>
      <TableBody>{products.isLoading || products.isError || !products.data?.items.length ? <TableRow><TableCell colSpan={7} className="h-20 text-center text-muted-foreground">{t(products.isLoading ? "common.loading" : products.isError ? "common.failedToLoad" : "creditProductDialog.empty")}</TableCell></TableRow> : products.data.items.map((product) => <TableRow key={product.key} className="h-20">
        <TableCell><div className="max-w-64 truncate" title={name(product)}><ListName onClick={() => open(product, false)}>{product.emoji} {name(product)}</ListName></div><div className="max-w-64 truncate text-xs text-muted-foreground" title={product.key}>{product.key}</div></TableCell>
        <TableCell>{t(`creditProducts.categories.${product.category}`, { defaultValue: product.category })}</TableCell><TableCell className="tabular-nums">{product.coins.toLocaleString()}</TableCell>
        <TableCell><Switch checked={product.enabled} disabled aria-label={t("creditProducts.enabled")} /></TableCell><TableCell><Switch checked={product.subscription_only} disabled aria-label={t("creditProducts.subscriptionOnly")} /></TableCell><TableCell><Switch checked={product.is_launched} disabled aria-label={t("creditProducts.isLaunched")} /></TableCell>
        <TableCell className="text-end"><ListActions actions={[{ label: t("listActions.details"), disabled: save.isPending, onSelect: () => open(product, false) }, { label: t("common.edit"), disabled: save.isPending, onSelect: () => open(product, true) }]} /></TableCell>
      </TableRow>)}</TableBody>
    </Table></div>
    <Dialog open={dialog !== null} onOpenChange={(isOpen) => { if (!isOpen) close(); }}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl" onEscapeKeyDown={(event) => { if (save.isPending) event.preventDefault(); }} onInteractOutside={(event) => { if (save.isPending) event.preventDefault(); }}>
        <DialogHeader><DialogTitle>{t(dialog?.editing ? "creditProductDialog.edit" : "creditProductDialog.details")}</DialogTitle><DialogDescription>{dialog ? `${name(dialog.product)} · ${dialog.product.key}` : ""}</DialogDescription></DialogHeader>
        {draft && <div className="space-y-4">
          <p className="break-words text-sm text-muted-foreground">{t(draft.description_key, { defaultValue: draft.description_key || "—" })}</p>
          <div className="grid grid-cols-2 gap-4 text-sm"><div><Label>{t("creditProducts.category")}</Label><p className="mt-1">{t(`creditProducts.categories.${draft.category}`, { defaultValue: draft.category })}</p></div><div><Label>{t("creditProductDialog.sortOrder")}</Label><p className="mt-1">{draft.sort_order}</p></div></div>
          <div className="space-y-2"><Label htmlFor="credit-product-coins">{t("creditProducts.coins")}</Label><Input id="credit-product-coins" type="number" min={1} max={100000} step={1} value={coins} disabled={!editable} onChange={(event) => setCoins(event.target.value)} />{dialog?.editing && !validCoins && <p className="text-sm text-destructive">{t("creditProductDialog.invalidCoins")}</p>}</div>
          {(["enabled", "subscription_only", "is_launched"] as const).map((field) => {
            const label = t(field === "enabled" ? "creditProducts.enabled" : field === "subscription_only" ? "creditProducts.subscriptionOnly" : "creditProducts.isLaunched");
            return <div key={field} className="flex items-center justify-between gap-4"><Label htmlFor={`credit-product-${field}`}>{label}</Label><Switch id={`credit-product-${field}`} checked={draft[field]} disabled={!editable} onCheckedChange={(checked) => setDraft((current) => current ? { ...current, [field]: checked } : current)} /></div>;
          })}
          {draft.category === "date" && <>
            <div className="space-y-2"><Label htmlFor="credit-product-background">{t("creditProducts.sceneBackground")}</Label><Input id="credit-product-background" value={draft.scene_background_url ?? ""} disabled={!editable} placeholder={t("creditProducts.sceneBackgroundHint")} onChange={(event) => setDraft({ ...draft, scene_background_url: event.target.value })} /></div>
            <div className="space-y-2"><Label htmlFor="credit-product-audio">{t("creditProducts.sceneAudio")}</Label><Input id="credit-product-audio" value={draft.scene_audio_url ?? ""} disabled={!editable} onChange={(event) => setDraft({ ...draft, scene_audio_url: event.target.value })} /></div>
            {draft.scene_background_url && <img src={draft.scene_background_url} alt={t("creditProducts.sceneBackground")} className="h-40 w-full rounded-lg object-cover" loading="lazy" />}
          </>}
          {!dialog?.editing && <div className="space-y-2"><Label>{t("creditProductDialog.metadata")}</Label><pre className="max-h-64 overflow-auto rounded-md bg-muted p-3 text-xs">{JSON.stringify(draft.metadata, null, 2)}</pre></div>}
        </div>}
        <DialogFooter><Button variant="outline" disabled={save.isPending} onClick={close}>{t(dialog?.editing ? "common.cancel" : "creditProductClose")}</Button>
          {dialog?.editing ? <Button disabled={save.isPending || !validCoins || !changed} onClick={() => { if (!draft || !validCoins) return; const { scene_background_url, scene_audio_url, ...product } = draft; save.mutate({ ...product, coins: Number(coins), ...(draft.category === "date" ? { scene_background_url: scene_background_url?.trim(), scene_audio_url: scene_audio_url?.trim() } : {}) }); }}>{t(save.isPending ? "common.loading" : "common.save")}</Button> : dialog && <Button onClick={() => open(dialog.product, true)}>{t("common.edit")}</Button>}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>;
}
