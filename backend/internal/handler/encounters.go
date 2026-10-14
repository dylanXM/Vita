package handler

import (
 "context"
 "database/sql"
 "encoding/json"
 "fmt"
 "net/http"
 "net/url"
 "strings"
 "time"
 "unicode/utf8"

 "github.com/gin-gonic/gin"
 "github.com/google/uuid"
 "github.com/lib/pq"
 "vita/internal/agent"
 "vita/internal/credits"
 "vita/internal/db"
)

type encounterCharacter struct {
 ID string `json:"id"`
 Name string `json:"name"`
 Gender string `json:"gender"`
 Personality string `json:"personality"`
 Persona string `json:"persona"`
 Description string `json:"description"`
 CoverURL string `json:"cover_url"`
 AvatarURL string `json:"avatar_url"`
 Enabled bool `json:"enabled"`
 SortOrder int `json:"sort_order"`
}

const encounterColumns = "id,name,gender,personality,persona,description,cover_url,avatar_url,enabled,sort_order"
func scanEncounter(row interface{ Scan(...any) error }, item *encounterCharacter) error {
 return row.Scan(&item.ID,&item.Name,&item.Gender,&item.Personality,&item.Persona,&item.Description,&item.CoverURL,&item.AvatarURL,&item.Enabled,&item.SortOrder)
}
func validEncounterURL(raw string) bool {
 if strings.HasPrefix(raw,"/v1/admin-images/") && !strings.Contains(raw,"..") && !strings.ContainsAny(raw,"?#") { _,err:=uuid.Parse(strings.TrimPrefix(raw,"/v1/admin-images/")); return err==nil }
 parsed, err := url.Parse(raw)
 return err == nil && (parsed.Scheme == "https" || parsed.Scheme == "http") && parsed.Host != "" && parsed.User == nil
}
func AdminListEncounterCharacters(c *gin.Context) { listEncounterCharacters(c,true) }
func ListEncounterCharacters(c *gin.Context) { listEncounterCharacters(c,false) }
func listEncounterCharacters(c *gin.Context, admin bool) {
 query := "SELECT " + encounterColumns + " FROM encounter_characters WHERE owner_id IS NULL"
 args := []any{}
 if !admin {
  query = "SELECT " + encounterColumns + " FROM encounter_characters WHERE enabled AND (owner_id IS NULL OR owner_id=$1)"
  args = append(args,c.GetString("user_id"))
 }
 rows, err := db.Get().QueryContext(c.Request.Context(),query+" ORDER BY sort_order,created_at,id",args...)
 if err != nil { c.JSON(500,gin.H{"error":"cannot load characters"}); return }
 defer rows.Close()
 items := []encounterCharacter{}
 for rows.Next() {
  var item encounterCharacter
  if scanEncounter(rows,&item) != nil { c.JSON(500,gin.H{"error":"cannot read characters"}); return }
  if !admin { item.Persona = "" }
  items = append(items,item)
 }
 if rows.Err() != nil { c.JSON(500,gin.H{"error":"cannot read characters"}); return }
 c.JSON(200,gin.H{"items":items})
}
func AdminSaveEncounterCharacter(c *gin.Context) { saveEncounterCharacter(c,true) }
func CreateCustomEncounterCharacter(c *gin.Context) { saveEncounterCharacter(c,false) }
func saveEncounterCharacter(c *gin.Context, admin bool) {
 var item encounterCharacter
 if c.ShouldBindJSON(&item) != nil { c.JSON(400,gin.H{"error":"invalid character"}); return }
 item.Name = strings.TrimSpace(item.Name)
 if item.Name == "" || utf8.RuneCountInString(item.Name)>80 || utf8.RuneCountInString(item.Persona)>4000 || utf8.RuneCountInString(item.Description)>500 || utf8.RuneCountInString(item.Personality)>200 || !validEncounterURL(item.CoverURL) || (item.AvatarURL!="" && !validEncounterURL(item.AvatarURL)) || (item.Gender!="male" && item.Gender!="female" && item.Gender!="other") {
  c.JSON(400,gin.H{"error":"invalid character fields"}); return
 }
 id := c.Param("id")
 if id != "" {
  if _,err:=uuid.Parse(id); err!=nil { c.JSON(400,gin.H{"error":"invalid character id"}); return }
  result,err:=db.Get().ExecContext(c.Request.Context(),`UPDATE encounter_characters SET name=$2,gender=$3,personality=$4,persona=$5,description=$6,cover_url=$7,avatar_url=$8,enabled=$9,sort_order=$10 WHERE id=$1 AND owner_id IS NULL`,id,item.Name,item.Gender,item.Personality,item.Persona,item.Description,item.CoverURL,item.AvatarURL,item.Enabled,item.SortOrder)
  if err!=nil { c.JSON(500,gin.H{"error":"cannot save character"}); return }
  n,_:=result.RowsAffected(); if n!=1 { c.JSON(404,gin.H{"error":"character not found"}); return }
 } else {
  id=uuid.NewString(); var owner any
  if !admin { owner=c.GetString("user_id"); item.Enabled=true; item.SortOrder=0 }
  _,err:=db.Get().ExecContext(c.Request.Context(),`INSERT INTO encounter_characters(id,owner_id,name,gender,personality,persona,description,cover_url,avatar_url,enabled,sort_order) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,id,owner,item.Name,item.Gender,item.Personality,item.Persona,item.Description,item.CoverURL,item.AvatarURL,item.Enabled,item.SortOrder)
  if err!=nil { c.JSON(500,gin.H{"error":"cannot create character"}); return }
 }
 item.ID=id; c.JSON(200,item)
}

func EncounterPreferences(c *gin.Context) {
 user:=c.GetString("user_id")
 var input struct { Gender string `json:"gender"`; Personality string `json:"personality"` }
 if c.Request.Method==http.MethodPut {
  if c.ShouldBindJSON(&input)!=nil || (input.Gender!="" && input.Gender!="male" && input.Gender!="female" && input.Gender!="other") || utf8.RuneCountInString(input.Personality)>200 { c.JSON(400,gin.H{"error":"invalid preferences"}); return }
  if _,err:=db.Get().ExecContext(c.Request.Context(),`INSERT INTO encounter_preferences(user_id,gender,personality) VALUES($1,$2,$3) ON CONFLICT(user_id) DO UPDATE SET gender=$2,personality=$3`,user,input.Gender,input.Personality); err!=nil { c.JSON(500,gin.H{"error":"cannot save preferences"}); return }
 } else {
  err:=db.Get().QueryRowContext(c.Request.Context(),`SELECT gender,personality FROM encounter_preferences WHERE user_id=$1`,user).Scan(&input.Gender,&input.Personality)
  if err==sql.ErrNoRows { c.JSON(200,gin.H{"configured":false}); return }
  if err!=nil { c.JSON(500,gin.H{"error":"cannot load preferences"}); return }
 }
 c.JSON(200,gin.H{"configured":true,"gender":input.Gender,"personality":input.Personality})
}
func StartEncounterConversation(c *gin.Context) {
 var input struct { CharacterID string `json:"character_id"` }
 if c.ShouldBindJSON(&input)!=nil { c.JSON(400,gin.H{"error":"invalid character"}); return }
 if _,err:=uuid.Parse(input.CharacterID); err!=nil { c.JSON(400,gin.H{"error":"invalid character"}); return }
 var id string
 err:=db.Get().QueryRowContext(c.Request.Context(),`INSERT INTO encounter_conversations(id,user_id,character_id) SELECT $1,$2,id FROM encounter_characters WHERE id=$3 AND enabled AND (owner_id IS NULL OR owner_id=$2) ON CONFLICT(user_id,character_id) DO UPDATE SET updated_at=CURRENT_TIMESTAMP RETURNING id`,uuid.NewString(),c.GetString("user_id"),input.CharacterID).Scan(&id)
 if err!=nil { c.JSON(404,gin.H{"error":"character unavailable"}); return }
 c.JSON(200,gin.H{"id":id})
}
func ListEncounterConversations(c *gin.Context) {
 rows,err:=db.Get().QueryContext(c.Request.Context(),`SELECT v.id,r.name,r.avatar_url,r.cover_url FROM encounter_conversations v JOIN encounter_characters r ON r.id=v.character_id WHERE v.user_id=$1 ORDER BY v.updated_at DESC`,c.GetString("user_id"))
 if err!=nil { c.JSON(500,gin.H{"error":"cannot load conversations"}); return }; defer rows.Close()
 items:=[]gin.H{}
 for rows.Next() { var id,name,avatar,cover string; if rows.Scan(&id,&name,&avatar,&cover)!=nil { c.JSON(500,gin.H{"error":"cannot read conversations"}); return }; items=append(items,gin.H{"id":id,"name":name,"avatar_url":avatar,"cover_url":cover}) }
 if rows.Err()!=nil { c.JSON(500,gin.H{"error":"cannot read conversations"}); return }; c.JSON(200,gin.H{"items":items})
}
func encounterOwned(c *gin.Context) bool {
 if _,err:=uuid.Parse(c.Param("id")); err!=nil { c.JSON(404,gin.H{"error":"conversation not found"}); return false }
 var exists bool
 if db.Get().QueryRowContext(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM encounter_conversations WHERE id=$1 AND user_id=$2)`,c.Param("id"),c.GetString("user_id")).Scan(&exists)!=nil || !exists { c.JSON(404,gin.H{"error":"conversation not found"}); return false }; return true
}
func GetEncounterMessages(c *gin.Context) {
 if !encounterOwned(c) { return }
 rows,err:=db.Get().QueryContext(c.Request.Context(),`SELECT id,sender_type,content,media_url FROM (SELECT id,sender_type,content,media_url,created_at FROM encounter_messages WHERE conversation_id=$1 ORDER BY created_at DESC,id DESC LIMIT 100) m ORDER BY created_at,id`,c.Param("id"))
 if err!=nil { c.JSON(500,gin.H{"error":"cannot load messages"}); return }; defer rows.Close()
 items:=[]gin.H{}
 for rows.Next() { var id,sender,content,media string; if rows.Scan(&id,&sender,&content,&media)!=nil { c.JSON(500,gin.H{"error":"cannot read messages"}); return }; items=append(items,gin.H{"id":id,"sender_type":sender,"content":content,"media_url":media}) }
 if rows.Err()!=nil { c.JSON(500,gin.H{"error":"cannot read messages"}); return }; c.JSON(200,gin.H{"items":items})
}

func SendEncounterMessage(c *gin.Context) {
 if !encounterOwned(c) { return }
 var input struct { Content string `json:"content"`; Key string `json:"idempotency_key"`; Product string `json:"product_key"`; Coins int `json:"quoted_coins"` }
 if c.ShouldBindJSON(&input)!=nil || strings.TrimSpace(input.Content)=="" || utf8.RuneCountInString(input.Content)>2000 || len(input.Key)>80 || input.Key=="" { c.JSON(400,gin.H{"error":"invalid message"}); return }
 if companionAgent==nil { c.JSON(503,gin.H{"error":"model service unavailable"}); return }
 ctx,cancel:=context.WithTimeout(context.WithoutCancel(c.Request.Context()),5*time.Minute); defer cancel()
 _,errRecovery:=db.Get().ExecContext(ctx,`UPDATE encounter_requests r SET status='failed' WHERE conversation_id=$1 AND status='processing' AND created_at<CURRENT_TIMESTAMP-interval '10 minutes' AND (spend_id IS NULL OR EXISTS(SELECT 1 FROM credit_spends s WHERE s.id=r.spend_id AND s.status='refunded'))`,c.Param("id"))
 if errRecovery!=nil { c.JSON(500,gin.H{"error":"cannot recover requests"}); return }
 var character encounterCharacter
 err:=scanEncounter(db.Get().QueryRowContext(ctx,"SELECT "+"r.id,r.name,r.gender,r.personality,r.persona,r.description,r.cover_url,r.avatar_url,r.enabled,r.sort_order"+` FROM encounter_characters r JOIN encounter_conversations v ON v.character_id=r.id WHERE v.id=$1 AND v.user_id=$2 AND r.enabled`,c.Param("id"),c.GetString("user_id")),&character)
 if err!=nil { c.JSON(404,gin.H{"error":"character unavailable"}); return }
 var product *credits.Product
 if input.Product!="" {
  products,e:=credits.ListProducts(ctx,db.Get(),currentEnvironment(),"")
  if e!=nil { c.JSON(503,gin.H{"error":"products unavailable"}); return }
  for i:=range products { if products[i].Key==input.Product { product=&products[i]; break } }
  if input.Product=="encounter_video" { product,err=loadEncounterVideo(ctx); if err!=nil || !product.Enabled || !product.IsLaunched { c.JSON(409,gin.H{"error":"video unavailable"}); return } }
  if product==nil || (product.Category!="gift" && product.Category!="photo") { c.JSON(400,gin.H{"error":"unsupported encounter product"}); return }
  if product.Coins!=input.Coins { c.JSON(409,gin.H{"code":"price_changed","error":"price changed"}); return }
 }
 requestID:=uuid.NewString()
 result,err:=db.Get().ExecContext(ctx,`INSERT INTO encounter_requests(id,conversation_id,request_key,content,product_key,quoted_coins) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(conversation_id,request_key) DO NOTHING`,requestID,c.Param("id"),input.Key,input.Content,input.Product,input.Coins)
 if err!=nil { if e,ok:=err.(*pq.Error); ok && e.Code=="23505" { c.JSON(409,gin.H{"code":"request_processing","error":"another reply is processing"}); return }; c.JSON(500,gin.H{"error":"cannot create request"}); return }
 n,_:=result.RowsAffected()
 if n==0 {
  var content,key,status string; var coins int
  err=db.Get().QueryRowContext(ctx,`SELECT content,product_key,quoted_coins,status FROM encounter_requests WHERE conversation_id=$1 AND request_key=$2`,c.Param("id"),input.Key).Scan(&content,&key,&coins,&status)
  if err!=nil { c.JSON(500,gin.H{"error":"cannot load request"}); return }
  if content!=input.Content || key!=input.Product || coins!=input.Coins { c.JSON(409,gin.H{"error":"request key already used"}); return }
  if status=="completed" { c.JSON(200,gin.H{"status":status,"idempotent":true}); return }
  c.JSON(409,gin.H{"code":"request_"+status,"error":"request "+status}); return
 }
 var spend *credits.Reservation
 fail:=func(e error) {
  recovery,done:=context.WithTimeout(context.Background(),10*time.Second); defer done()
  if spend!=nil { if refundErr:=credits.Refund(recovery,db.Get(),spend.ID,e.Error()); refundErr!=nil { c.JSON(500,gin.H{"code":"refund_unconfirmed","error":"refund could not be confirmed"}); return } }
  _,_=db.Get().ExecContext(recovery,`UPDATE encounter_requests SET status='failed' WHERE id=$1 AND status='processing'`,requestID)
  c.JSON(422,gin.H{"error":e.Error(),"refunded":spend!=nil})
 }
 if product!=nil {
  spend,err=credits.Reserve(ctx,db.Get(),credits.ReserveParams{UserID:c.GetString("user_id"),Environment:currentEnvironment(),Platform:requestPlatform(c),ProductKey:input.Product,IdempotencyKey:"encounter:"+requestID,ReferenceType:"encounter",Metadata:map[string]any{"quoted_coins":input.Coins,"request_id":requestID,"conversation_id":c.Param("id")}})
  if err!=nil { _,_=db.Get().ExecContext(ctx,`UPDATE encounter_requests SET status='failed' WHERE id=$1`,requestID); writeSpendError(c,err); return }
  if _,err=db.Get().ExecContext(ctx,`UPDATE encounter_requests SET spend_id=$2 WHERE id=$1`,requestID,spend.ID); err!=nil { fail(err); return }
 }
 history:=[]agent.ChatMessage{}
 rows,err:=db.Get().QueryContext(ctx,`SELECT sender_type,content FROM (SELECT sender_type,content,created_at,id FROM encounter_messages WHERE conversation_id=$1 ORDER BY created_at DESC,id DESC LIMIT 30) m ORDER BY created_at,id`,c.Param("id"))
 if err!=nil { fail(err); return }
 for rows.Next() { var sender,text string; if err=rows.Scan(&sender,&text); err!=nil { rows.Close(); fail(err); return }; if sender=="character" { sender="assistant" }; history=append(history,agent.ChatMessage{Role:sender,Content:text}) }; err=rows.Err(); rows.Close(); if err!=nil { fail(err); return }
 history=append(history,agent.ChatMessage{Role:"user",Content:input.Content})
 var reply,media string
 if product!=nil && product.Key=="encounter_video" { modelID,_:=product.Metadata["model_id"].(string); duration,_:=product.Metadata["duration"].(float64); media,err=companionAgent.VideoEncounter(ctx,c.GetString("user_id"),modelID,int(duration),character.CoverURL,input.Content) } else if product!=nil && product.Category=="photo" { media,err=companionAgent.PhotoEncounter(ctx,c.GetString("user_id"),character.Name,character.Persona,character.CoverURL,input.Content) } else { reply,err=companionAgent.ReplyEncounter(ctx,c.GetString("user_id"),character.Name,character.Persona,c.GetHeader("Accept-Language"),history) }
 if err!=nil { fail(err); return }
 settlement,done:=context.WithTimeout(context.Background(),10*time.Second); defer done()
 tx,err:=db.Get().BeginTx(settlement,nil); if err!=nil { fail(err); return }; defer tx.Rollback()
 if spend!=nil {
  var status string; err=tx.QueryRowContext(settlement,`SELECT status FROM credit_spends WHERE id=$1 FOR UPDATE`,spend.ID).Scan(&status)
  if err==nil && status!="reserved" { err=fmt.Errorf("spend no longer reserved") }
 }
 if err==nil { _,err=tx.ExecContext(settlement,`INSERT INTO encounter_messages(id,conversation_id,request_id,sender_type,content,created_at) VALUES($1,$2,$3,'user',$4,CURRENT_TIMESTAMP)`,uuid.NewString(),c.Param("id"),requestID,input.Content) }
 messageID:=uuid.NewString()
 if err==nil { _,err=tx.ExecContext(settlement,`INSERT INTO encounter_messages(id,conversation_id,request_id,sender_type,content,media_url,created_at) VALUES($1,$2,$3,'character',$4,$5,CURRENT_TIMESTAMP+interval '1 microsecond')`,messageID,c.Param("id"),requestID,reply,media) }
 if err==nil && spend!=nil { encoded,_:=json.Marshal(gin.H{"message_id":messageID,"media_url":media}); _,err=tx.ExecContext(settlement,`UPDATE credit_spends SET status='completed',reference_id=$2,result=$3,completed_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1`,spend.ID,messageID,string(encoded)) }
 if err==nil { _,err=tx.ExecContext(settlement,`UPDATE encounter_requests SET status='completed' WHERE id=$1`,requestID) }
 if err==nil { _,err=tx.ExecContext(settlement,`UPDATE encounter_conversations SET updated_at=CURRENT_TIMESTAMP WHERE id=$1`,c.Param("id")) }
 if err!=nil { tx.Rollback(); fail(err); return }
 if err=tx.Commit(); err!=nil {
  var status string
  if db.Get().QueryRowContext(settlement,`SELECT status FROM encounter_requests WHERE id=$1`,requestID).Scan(&status)!=nil { c.JSON(503,gin.H{"error":"settlement unknown; retry original request","code":"settlement_pending"}); return }
  if status!="completed" { fail(err); return }
 }
 c.JSON(200,gin.H{"status":"completed"})
}
