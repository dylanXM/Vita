import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { creditProductsApi } from "@/api/admin";
import type { CreditProduct } from "@/api/types";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

export function CreditProductsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const environment = "prod" as const;
  const products = useQuery({
    queryKey: ["credit-products", environment],
    queryFn: ({ signal }) => creditProductsApi.list(environment, signal),
  });
  const save = useMutation({
    mutationFn: (product: CreditProduct) => creditProductsApi.update(environment, product.key, product),
    onSuccess: () => {
      toast.success(t("creditProducts.saved"));
      void queryClient.invalidateQueries({ queryKey: ["credit-products", environment] });
    },
    onError: () => toast.error(t("common.failedToLoad")),
  });

  return (
    <div className="space-y-6">
      <PageHeader title={t("creditProducts.title")} description={t("creditProducts.description")} />
      <div className="overflow-hidden rounded-lg border bg-card">
        <Table>
          <TableHeader><TableRow>
            <TableHead>{t("creditProducts.product")}</TableHead>
            <TableHead>{t("creditProducts.category")}</TableHead>
            <TableHead className="w-32">{t("creditProducts.coins")}</TableHead>
            <TableHead className="w-28">{t("creditProducts.enabled")}</TableHead>
            <TableHead>{t("creditProducts.subscriptionOnly")}</TableHead>
            <TableHead>{t("creditProducts.isLaunched")}</TableHead>
            <TableHead className="w-24" />
          </TableRow></TableHeader>
          <TableBody>
            {(products.data?.items ?? []).map((product) => (
              <CreditProductRow key={product.key} product={product} saving={save.isPending} onSave={(next) => save.mutate(next)} />
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

function CreditProductRow({ product, saving, onSave }: { product: CreditProduct; saving: boolean; onSave: (product: CreditProduct) => void }) {
  const { t } = useTranslation();
  const [coins, setCoins] = useState(product.coins);
  const [enabled, setEnabled] = useState(product.enabled);
  const [subscriptionOnly, setSubscriptionOnly] = useState(product.subscription_only);
  const [isLaunched, setIsLaunched] = useState(product.is_launched);
  useEffect(() => { setCoins(product.coins); setEnabled(product.enabled); setSubscriptionOnly(product.subscription_only); setIsLaunched(product.is_launched); }, [product]);
  return (
    <TableRow>
      <TableCell><div className="font-medium">{product.emoji} {product.key}</div><div className="text-xs text-muted-foreground">{product.name_key}</div></TableCell>
      <TableCell>{product.category}</TableCell>
      <TableCell><Input type="number" min={1} value={coins} onChange={(event) => setCoins(Number(event.target.value))} /></TableCell>
      <TableCell><input aria-label={t("creditProducts.enabled")} type="checkbox" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} /></TableCell>
      <TableCell><input aria-label={t("creditProducts.subscriptionOnly")} type="checkbox" checked={subscriptionOnly} onChange={(event) => setSubscriptionOnly(event.target.checked)} /></TableCell>
      <TableCell><input aria-label={t("creditProducts.isLaunched")} type="checkbox" checked={isLaunched} onChange={(event) => setIsLaunched(event.target.checked)} /></TableCell>
      <TableCell><Button size="sm" disabled={saving || coins < 1} onClick={() => onSave({ ...product, coins, enabled, subscription_only: subscriptionOnly, is_launched: isLaunched })}>{t("common.save")}</Button></TableCell>
    </TableRow>
  );
}
