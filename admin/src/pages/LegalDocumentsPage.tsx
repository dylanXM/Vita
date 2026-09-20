import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { envApi, legalDocumentsApi } from "@/api/admin";
import type { Environment, LegalDocument, LegalDocumentInput, LegalDocumentType } from "@/api/types";
import { ENVIRONMENTS } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/sonner";

const emptyForm = (environment: Environment, document_type: LegalDocumentType): LegalDocumentInput => ({
  environment, document_type, version: "", title: document_type === "privacy" ? "Privacy Policy" : "Terms of Service", summary: "", content: "",
});

export function LegalDocumentsPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const [documentType, setDocumentType] = useState<LegalDocumentType>("privacy");
  const [editing, setEditing] = useState<LegalDocument | "new" | null>(null);
  const activeEnv = environment ?? serverEnv.data?.environment;
  const queryKey = ["legal-documents", activeEnv, documentType];
  const query = useQuery({
    queryKey,
    queryFn: ({ signal }) => legalDocumentsApi.list(activeEnv!, documentType, signal),
    enabled: Boolean(activeEnv),
  });
  const refresh = () => queryClient.invalidateQueries({ queryKey: ["legal-documents"] });
  const activate = useMutation({ mutationFn: legalDocumentsApi.activate, onSuccess: () => { void refresh(); toast.success(t("legal.activated")); }, onError: (e) => toast.error(errorMessage(e)) });
  const remove = useMutation({ mutationFn: legalDocumentsApi.remove, onSuccess: () => { void refresh(); toast.success(t("legal.deleted")); }, onError: (e) => toast.error(errorMessage(e)) });

  return <div className="space-y-6">
    <PageHeader title={t("legal.title")} description={t("legal.desc")} actions={<div className="flex gap-2">
      <Select value={documentType} onValueChange={(value) => setDocumentType(value as LegalDocumentType)}><SelectTrigger className="w-44"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="privacy">{t("legal.privacy")}</SelectItem><SelectItem value="terms">{t("legal.terms")}</SelectItem></SelectContent></Select>
      <Select value={activeEnv ?? ""} onValueChange={(value) => setEnvironment(value as Environment)}><SelectTrigger className="w-32"><SelectValue /></SelectTrigger><SelectContent>{ENVIRONMENTS.map((value) => <SelectItem key={value} value={value}>{value}</SelectItem>)}</SelectContent></Select>
      <Button disabled={!activeEnv} onClick={() => setEditing("new")}>{t("legal.create")}</Button>
    </div>} />
    <p className="text-sm text-muted-foreground">{t("legal.immutableHint")}</p>
    {query.isLoading ? <Skeleton className="h-56 w-full" /> : <div className="overflow-hidden rounded-lg border"><Table>
      <TableHeader><TableRow><TableHead>{t("legal.version")}</TableHead><TableHead>{t("content.title")}</TableHead><TableHead>{t("content.status")}</TableHead><TableHead>{t("legal.updatedAt")}</TableHead><TableHead>{t("content.operator")}</TableHead><TableHead className="text-end">{t("content.actions")}</TableHead></TableRow></TableHeader>
      <TableBody>{query.data?.items.length ? query.data.items.map((item) => <TableRow key={item.id}>
        <TableCell className="font-mono">{item.version}</TableCell><TableCell>{item.title}</TableCell><TableCell>{item.is_effective ? <Badge>{t("legal.effective")}</Badge> : item.published_at ? <Badge variant="secondary">{t("legal.historical")}</Badge> : <Badge variant="outline">{t("legal.draft")}</Badge>}</TableCell>
        <TableCell>{new Date(item.updated_at).toLocaleString()}</TableCell><TableCell>{item.updated_by || "system"}</TableCell>
        <TableCell><div className="flex justify-end gap-2">{!item.is_effective && <Button size="sm" variant="outline" disabled={activate.isPending} onClick={() => activate.mutate(item.id)}>{t("legal.activate")}</Button>}{!item.published_at && <><Button size="sm" variant="outline" onClick={() => setEditing(item)}>{t("legal.edit")}</Button><Button size="sm" variant="destructive" disabled={remove.isPending} onClick={() => { if (window.confirm(t("legal.deleteConfirm"))) remove.mutate(item.id); }}>{t("legal.delete")}</Button></>}</div></TableCell>
      </TableRow>) : <TableRow><TableCell colSpan={6} className="h-28 text-center text-muted-foreground">{t("legal.empty")}</TableCell></TableRow>}</TableBody>
    </Table></div>}
    {activeEnv && editing && <LegalDocumentDialog environment={activeEnv} documentType={documentType} document={editing === "new" ? undefined : editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); void refresh(); }} />}
  </div>;
}

function LegalDocumentDialog({ environment, documentType, document, onClose, onSaved }: { environment: Environment; documentType: LegalDocumentType; document?: LegalDocument; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation();
  const [form, setForm] = useState<LegalDocumentInput>(document ?? emptyForm(environment, documentType));
  const save = useMutation({ mutationFn: () => document ? legalDocumentsApi.update(document.id, form) : legalDocumentsApi.create(form), onSuccess: () => { toast.success(t("legal.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e)) });
  const valid = form.version.trim() && form.title.trim() && form.content.trim();
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto"><DialogHeader><DialogTitle>{document ? t("legal.edit") : t("legal.create")}</DialogTitle><DialogDescription>{t("legal.englishOnly")}</DialogDescription></DialogHeader>
    <div className="space-y-4"><div className="space-y-2"><Label>{t("legal.version")}</Label><Input value={form.version} onChange={(e) => setForm({ ...form, version: e.target.value })} placeholder="2026-10-01" /></div><div className="space-y-2"><Label>{t("content.title")}</Label><Input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></div><div className="space-y-2"><Label>{t("legal.summary")}</Label><Input value={form.summary} onChange={(e) => setForm({ ...form, summary: e.target.value })} /></div><div className="space-y-2"><Label>{t("legal.content")}</Label><textarea className="min-h-80 w-full rounded-md border bg-transparent px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" value={form.content} onChange={(e) => setForm({ ...form, content: e.target.value })} /></div></div>
    <DialogFooter><Button variant="outline" onClick={onClose}>{t("content.cancel")}</Button><Button disabled={!valid || save.isPending} onClick={() => save.mutate()}>{t("content.save")}</Button></DialogFooter>
  </DialogContent></Dialog>;
}
