package handler

import (
 "context"
 "encoding/json"
 "github.com/gin-gonic/gin"
 "vita/internal/credits"
 "vita/internal/db"
)

func loadEncounterVideo(ctx context.Context) (*credits.Product,error) {
 var item credits.Product; var raw string
 err:=db.Get().QueryRowContext(ctx,`SELECT product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::text,subscription_only,is_launched FROM credit_products WHERE environment=$1 AND product_key='encounter_video'`,currentEnvironment()).Scan(&item.Key,&item.Category,&item.NameKey,&item.DescriptionKey,&item.Emoji,&item.Coins,&item.Enabled,&item.SortOrder,&raw,&item.SubscriptionOnly,&item.IsLaunched)
 if err==nil { err=json.Unmarshal([]byte(raw),&item.Metadata) }; return &item,err
}
func EncounterCatalog(c *gin.Context) {
 products,err:=credits.ListProducts(c.Request.Context(),db.Get(),currentEnvironment(),"")
 if err!=nil { c.JSON(500,gin.H{"error":"catalog unavailable"}); return }
 items:=[]credits.Product{}
 for _,p:=range products { if (p.Category=="gift" || p.Category=="photo") && p.IsLaunched { items=append(items,p) } }
 if video,e:=loadEncounterVideo(c.Request.Context()); e==nil && video.Enabled && video.IsLaunched && companionAgent!=nil { modelID,_:=video.Metadata["model_id"].(string); duration,_:=video.Metadata["duration"].(float64); if companionAgent.CheckEncounterVideo(c.Request.Context(),modelID,int(duration))==nil { items=append(items,*video) } }
 var balance int
 if db.Get().QueryRowContext(c.Request.Context(),`SELECT credits_balance FROM users WHERE id=$1`,c.GetString("user_id")).Scan(&balance)!=nil { c.JSON(500,gin.H{"error":"balance unavailable"}); return }
 c.JSON(200,gin.H{"products":items,"balance":balance})
}
func AdminEncounterVideo(c *gin.Context) {
 if c.Request.Method=="PUT" {
  var input struct { Coins int `json:"coins"`; ModelID string `json:"model_id"`; Duration int `json:"duration"`; Enabled bool `json:"enabled"` }
  if c.ShouldBindJSON(&input)!=nil || input.Coins<1 || input.Coins>100000 || (input.Duration!=5 && input.Duration!=10) { c.JSON(400,gin.H{"error":"invalid video configuration"}); return }
  if input.Enabled { if companionAgent==nil { c.JSON(503,gin.H{"error":"model service unavailable"}); return }; if err:=companionAgent.CheckEncounterVideo(c.Request.Context(),input.ModelID,input.Duration); err!=nil { c.JSON(400,gin.H{"error":err.Error()}); return } }
  raw,_:=json.Marshal(gin.H{"hidden_from_catalog":true,"media_type":"video","model_id":input.ModelID,"duration":input.Duration})
  if _,err:=db.Get().ExecContext(c.Request.Context(),`UPDATE credit_products SET coins=$2,enabled=$3,is_launched=$3,metadata=$4 WHERE environment=$1 AND product_key='encounter_video'`,currentEnvironment(),input.Coins,input.Enabled,string(raw)); err!=nil { c.JSON(500,gin.H{"error":"cannot save video settings"}); return }
 }
 item,err:=loadEncounterVideo(c.Request.Context()); if err!=nil { c.JSON(500,gin.H{"error":"video settings unavailable"}); return }
 c.JSON(200,gin.H{"coins":item.Coins,"enabled":item.Enabled,"model_id":item.Metadata["model_id"],"duration":item.Metadata["duration"]})
}
