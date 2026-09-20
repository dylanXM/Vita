import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { creditProductsApi, envApi } from "@/api/admin";
import type { CreditProduct, Environment } from "@/api/types";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

export function CreditProductsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const env = useQuery({ queryKey: ["environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment>("dev");
  useEffect(() => {
    if (env.data?.environment) setEnvironment(env.data.environment);
  }, [env.data?.environment]);
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
      <PageHeader title={t("creditProducts.title")} description={t("creditProducts.description")} actions={
        <div className="w-44">
          <Select value={environment} onValueChange={(value) => setEnvironment(value as Environment)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="dev">Dev</SelectItem>
              <SelectItem value="beta">Beta</SelectItem>
              <SelectItem value="prod">Prod</SelectItem>
            </SelectContent>
          </Select>
        </div>
      } />
      <div className="overflow-hidden rounded-lg border bg-card">
        <Table>
          <TableHeader><TableRow>
            <TableHead>{t("creditProducts.product")}</TableHead>
            <TableHead>{t("creditProducts.category")}</TableHead>
            <TableHead className="w-32">{t("creditProducts.coins")}</TableHead>
            <TableHead className="w-28">{t("creditProducts.enabled")}</TableHead>
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
  useEffect(() => { setCoins(product.coins); setEnabled(product.enabled); }, [product]);
  return (
    <TableRow>
      <TableCell><div className="font-medium">{product.emoji} {product.key}</div><div className="text-xs text-muted-foreground">{product.name_key}</div></TableCell>
      <TableCell>{product.category}</TableCell>
      <TableCell><Input type="number" min={1} value={coins} onChange={(event) => setCoins(Number(event.target.value))} /></TableCell>
      <TableCell><input aria-label={t("creditProducts.enabled")} type="checkbox" checked={enabled} onChange={(event) => setEnabled(event.target.checked)} /></TableCell>
      <TableCell><Button size="sm" disabled={saving || coins < 1} onClick={() => onSave({ ...product, coins, enabled })}>{t("common.save")}</Button></TableCell>
    </TableRow>
  );
}
