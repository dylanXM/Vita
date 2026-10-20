import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { Link } from "react-router-dom";
import { api, errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { ListActions, ListName } from "@/components/list-actions";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type Feedback = { id: string; user_id: string; email: string; environment: string; content: string; created_at: string };
export function FeedbackPage() {
  const { t } = useTranslation();
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<Feedback | null>(null);
  const query = useQuery({ queryKey: ["feedback", page], queryFn: async ({ signal }) =>
    (await api.get<{ items: Feedback[]; has_more: boolean }>("/admin/feedback", { params: { page }, signal })).data });
  return <div className="space-y-6">
    <PageHeader title={t("feedback.title")} description={t("feedback.description")} actions={<Button variant="outline" onClick={() => query.refetch()}>{t("common.refresh")}</Button>} />
    {query.isError ? <p role="alert" className="text-destructive">{errorMessage(query.error)}</p> : query.isPending ? <p>{t("common.loading")}</p> : <>
      <div className="overflow-x-auto rounded-xl border"><table className="w-full text-sm"><thead><tr className="border-b text-left"><th className="p-3">{t("feedback.user")}</th><th className="p-3">{t("feedback.environment")}</th><th className="p-3">{t("feedback.time")}</th><th className="p-3">{t("feedback.content")}</th><th className="p-3">{t("feedback.details")}</th></tr></thead><tbody>
      {query.data.items.map(item => <tr key={item.id} className="border-b"><td className="p-3"><ListName onClick={() => setSelected(item)}>{item.email}</ListName></td><td className="p-3">{item.environment}</td><td className="p-3 whitespace-nowrap">{new Date(item.created_at).toLocaleString()}</td><td className="p-3"><p className="max-w-md truncate">{item.content}</p></td><td className="p-3 text-end"><ListActions actions={[{ label: t("listActions.details"), onSelect: () => setSelected(item) }]} /></td></tr>)}
      </tbody></table>{query.data.items.length === 0 && <p className="p-6 text-muted-foreground">{t("feedback.empty")}</p>}</div>
      <div className="flex items-center gap-3"><Button variant="outline" disabled={page === 1} onClick={() => setPage(page - 1)}>{t("feedback.previous")}</Button><span>{page}</span><Button variant="outline" disabled={!query.data.has_more} onClick={() => setPage(page + 1)}>{t("feedback.next")}</Button></div>
    </>}
    <Dialog open={selected !== null} onOpenChange={open => { if (!open) setSelected(null); }}><DialogContent><DialogHeader><DialogTitle>{t("feedback.details")}</DialogTitle></DialogHeader><Link className="text-sm text-muted-foreground hover:underline" to={`/users/${selected?.user_id}`}>{selected?.email}</Link><p className="max-h-[60vh] overflow-y-auto whitespace-pre-wrap break-words">{selected?.content}</p></DialogContent></Dialog>
  </div>;
}
