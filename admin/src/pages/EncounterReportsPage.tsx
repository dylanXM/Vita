import {useState} from "react";
import {useQuery,useMutation,useQueryClient} from "@tanstack/react-query";
import {useTranslation} from "react-i18next";
import {toast} from "sonner";
import {http,errorMessage} from "@/api/client";
import {PageHeader} from "@/components/page-header";
import {ListActions,ListName} from "@/components/list-actions";
import {Button} from "@/components/ui/button";
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from "@/components/ui/dialog";
import {Input} from "@/components/ui/input";
import {Select,SelectTrigger,SelectValue,SelectContent,SelectItem} from "@/components/ui/select";
type Report={id:string;character_id:string;character_name:string;user_id:string;email:string;reason:string;details:string;contact:string;status:string;review_note:string;created_at:string;reviewed_at?:string|null;reviewed_by?:string};
export function EncounterReportsPage(){
 const {t}=useTranslation();const cache=useQueryClient();const [page,setPage]=useState(1);const [selected,setSelected]=useState<Report|null>(null);const [status,setStatus]=useState("pending");const [note,setNote]=useState("");
 const query=useQuery({queryKey:["encounter-reports",page],queryFn:()=>http.get<{items:Report[];has_more:boolean}>(`/admin/encounter-reports?page=${page}`)});
 const review=useMutation({mutationFn:()=>http.put(`/admin/encounter-reports/${selected!.id}`,{status,review_note:note}),onSuccess:()=>{setSelected(null);void cache.invalidateQueries({queryKey:["encounter-reports"]});},onError:err=>toast.error(errorMessage(err))});
 const open=(r:Report)=>{setSelected(r);setStatus(r.status);setNote(r.review_note);};
 return <div className="space-y-6"><PageHeader title={t("encounters.reports")} description={t("encounters.reportPolicy")}/>{query.isError&&<Button onClick={()=>void query.refetch()}>{t("common.refresh")}</Button>}
 <div className="overflow-x-auto rounded-xl border"><table className="w-full text-sm"><thead><tr>{["name","reporter","reason","status","time","actions"].map(k=><th key={k} className="p-3 text-start">{t(`encounters.${k}`)}</th>)}</tr></thead><tbody>{(query.data?.items??[]).map(r=><tr key={r.id} className="border-t"><td className="p-3"><ListName onClick={()=>open(r)}>{r.character_name}</ListName></td><td className="p-3">{r.email}</td><td className="p-3">{t(`encounters.reason_${r.reason}`)}</td><td className="p-3">{t(`encounters.status_${r.status}`)}</td><td className="p-3">{new Date(r.created_at).toLocaleString()}</td><td className="p-3"><ListActions actions={[{label:t("listActions.details"),onSelect:()=>open(r)}]}/></td></tr>)}</tbody></table></div>
 <div className="flex gap-3"><Button variant="outline" disabled={page===1} onClick={()=>setPage(page-1)}>{t("feedback.previous")}</Button><Button variant="outline" disabled={!query.data?.has_more} onClick={()=>setPage(page+1)}>{t("feedback.next")}</Button></div>
 <Dialog open={selected!==null} onOpenChange={open=>{if(!open&&!review.isPending)setSelected(null);}}><DialogContent className="max-h-[85vh] overflow-y-auto"><DialogHeader><DialogTitle>{selected?.character_name}</DialogTitle><DialogDescription>{t("encounters.reportPolicy")}</DialogDescription></DialogHeader>{selected&&<div className="space-y-4"><p>{t("encounters.reporter")}: {selected.email}</p><p>{t("encounters.reason")}: {t(`encounters.reason_${selected.reason}`)}</p><p>{t("encounters.time")}: {new Date(selected.created_at).toLocaleString()}</p><p>{t("encounters.contact")}: {selected.contact||"—"}</p>{selected.reviewed_by&&<p>{t("encounters.reviewer")}: {selected.reviewed_by}</p>}{selected.reviewed_at&&<p>{t("encounters.reviewedAt")}: {new Date(selected.reviewed_at).toLocaleString()}</p><p className="whitespace-pre-wrap break-words">{selected.details}</p><Select value={status} onValueChange={setStatus}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent>{["pending","valid","dismissed"].map(s=><SelectItem key={s} value={s}>{t(`encounters.status_${s}`)}</SelectItem>)}</SelectContent></Select><Input value={note} maxLength={2000} onChange={e=>setNote(e.target.value)} placeholder={t("encounters.reviewNote")}/><Button disabled={review.isPending||note.trim().length<2} onClick={()=>review.mutate()}>{t("common.save")}</Button></div>}</DialogContent></Dialog></div>;
}
