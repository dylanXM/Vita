import {useEffect,useState} from "react";
import {api} from "@/api/client";
export function EncounterImage({url,characterId}:{url:string;characterId:string}){
 const [src,setSrc]=useState("");
 useEffect(()=>{
  let cancelled=false,objectURL="";const controller=new AbortController();setSrc("");
  if(!url)return()=>controller.abort();
  if(url.startsWith("/v1/media/")){
   void api.get<Blob>(`/admin/encounter-characters/${characterId}/images/${url.slice('/v1/media/'.length)}`,{responseType:"blob",signal:controller.signal}).then(response=>{if(!cancelled){objectURL=URL.createObjectURL(response.data);setSrc(objectURL);}}).catch(()=>{});
  }else{setSrc(url.startsWith("/v1/")?new URL(api.defaults.baseURL||"/v1",window.location.origin).origin+url:url);}
  return()=>{cancelled=true;controller.abort();if(objectURL)URL.revokeObjectURL(objectURL);};
 },[url,characterId]);
 return <div className="space-y-2">{src&&<img src={src} alt="" className="h-40 max-w-full rounded-lg object-contain"/>}<p className="break-all text-xs text-muted-foreground">{url||"—"}</p></div>;
}
