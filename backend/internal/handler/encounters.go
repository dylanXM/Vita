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
 "vita/internal/encounterart"
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
 ImageURLs []string `json:"image_urls"`
 Age int `json:"age"`
 Tags []string `json:"tags"`
 Followers int64 `json:"follower_count"`
 Following bool `json:"is_following"`
 Private bool `json:"is_private"`
}

const encounterColumns = "id,name,gender,personality,persona,description,cover_url,avatar_url,enabled,sort_order,image_urls,age,tags,(owner_id IS NOT NULL)"
func scanEncounter(row interface{ Scan(...any) error }, item *encounterCharacter) error {
 var images,tags string
 if err:=row.Scan(&item.ID,&item.Name,&item.Gender,&item.Personality,&item.Persona,&item.Description,&item.CoverURL,&item.AvatarURL,&item.Enabled,&item.SortOrder,&images,&item.Age,&tags,&item.Private); err!=nil { return err }
 if err:=json.Unmarshal([]byte(images),&item.ImageURLs);err!=nil{return err};return json.Unmarshal([]byte(tags),&item.Tags)
}
func validEncounterURL(raw string) bool {
 if len(raw)>2048 { return false }
 if strings.HasPrefix(raw,"/v1/encounter-art/") { _,err:=encounterart.Read(strings.TrimPrefix(raw,"/v1/encounter-art/"));return err==nil }
 if strings.HasPrefix(raw,"/v1/admin-images/") && !strings.Contains(raw,"..") && !strings.ContainsAny(raw,"?#") { _,err:=uuid.Parse(strings.TrimPrefix(raw,"/v1/admin-images/")); return err==nil }
 parsed, err := url.Parse(raw)
 if err==nil && strings.HasPrefix(parsed.Path,"/v1/media/"){return false}
 return err == nil && (parsed.Scheme == "https" || parsed.Scheme == "http") && parsed.Host != "" && parsed.User == nil
}
func AdminListEncounterCharacters(c *gin.Context) { listEncounterCharacters(c,true) }
func ListEncounterCharacters(c *gin.Context) { listEncounterCharacters(c,false) }
func listEncounterCharacters(c *gin.Context, admin bool) {
 query := "SELECT " + encounterColumns + " FROM encounter_characters"
 args := []any{}
 order := " ORDER BY sort_order,created_at,id"
 if !admin {
  var gender,personality string
  err:=db.Get().QueryRowContext(c.Request.Context(),`SELECT gender,personality FROM encounter_preferences WHERE user_id=$1`,c.GetString("user_id")).Scan(&gender,&personality)
  if err!=nil && err!=sql.ErrNoRows {c.JSON(500,gin.H{"error":"preferences unavailable"});return}
  query = "SELECT " + encounterColumns + " FROM encounter_characters r WHERE enabled AND (owner_id IS NULL OR owner_id=$1) AND ($2='' OR gender=$2)"
  args = []any{c.GetString("user_id"),gender,personality}
  order = ` ORDER BY (
   CASE WHEN $3<>'' AND (strpos(lower(personality),lower($3))>0 OR tags ? $3) THEN 60 ELSE 0 END
   - CASE WHEN EXISTS(SELECT 1 FROM encounter_reports q WHERE q.character_id=r.id AND q.user_id=$1 AND q.status<>'dismissed') THEN 1000 ELSE 0 END
   - LEAST((SELECT count(DISTINCT q.user_id) FROM encounter_reports q WHERE q.character_id=r.id AND q.status='valid'),5)*15
  ) DESC,sort_order,created_at,id`
 }
 rows, err := db.Get().QueryContext(c.Request.Context(),query+order,args...)
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
 rows.Close()
 if err:=fillEncounterFollowers(c.Request.Context(),items,c.GetString("user_id"));err!=nil{c.JSON(500,gin.H{"error":"followers unavailable"});return}
 c.JSON(200,gin.H{"items":items})
}
func AdminSaveEncounterCharacter(c *gin.Context) { saveEncounterCharacter(c,true) }
func CreateCustomEncounterCharacter(c *gin.Context) { saveEncounterCharacter(c,false) }
func saveEncounterCharacter(c *gin.Context, admin bool) {
 var item encounterCharacter
 if c.ShouldBindJSON(&item) != nil { c.JSON(400,gin.H{"error":"invalid character"}); return }
 item.Followers=0;item.Following=false;item.Private=!admin
 item.Name = strings.TrimSpace(item.Name)
 if item.Age==0 || item.Tags==nil {
  var age int;var raw string
  if admin && c.Param("id")!="" {
   if err:=db.Get().QueryRowContext(c.Request.Context(),`SELECT age,tags FROM encounter_characters WHERE id=$1 AND owner_id IS NULL`,c.Param("id")).Scan(&age,&raw);err!=nil{c.JSON(404,gin.H{"error":"character not found"});return}
   if item.Age==0{item.Age=age};if item.Tags==nil{if json.Unmarshal([]byte(raw),&item.Tags)!=nil{c.JSON(500,gin.H{"error":"invalid stored tags"});return}}
  }
  if item.Age==0{item.Age=25};if item.Tags==nil{item.Tags=[]string{}}
 }
 if item.Age<18 || item.Age>100 || len(item.Tags)>8 {c.JSON(400,gin.H{"error":"invalid age or tags"});return}
 for i,tag:=range item.Tags{item.Tags[i]=strings.TrimSpace(tag);if item.Tags[i]==""||utf8.RuneCountInString(item.Tags[i])>30{c.JSON(400,gin.H{"error":"invalid tag"});return}}
 if item.ImageURLs==nil {
  item.ImageURLs=[]string{item.CoverURL}
  if admin && c.Param("id")!="" {
   var raw string
   if err:=db.Get().QueryRowContext(c.Request.Context(),`SELECT image_urls FROM encounter_characters WHERE id=$1 AND owner_id IS NULL`,c.Param("id")).Scan(&raw); err==nil {
    var saved []string
    if json.Unmarshal([]byte(raw),&saved)==nil && len(saved)>1 { item.ImageURLs=append(item.ImageURLs,saved[1:]...) }
   }
  }
 }
 if len(item.ImageURLs)<1 || len(item.ImageURLs)>3 { c.JSON(400,gin.H{"error":"one to three character images required"});return }
 item.CoverURL=item.ImageURLs[0]
 validImage:=func(raw string)bool{
  if !admin && strings.HasPrefix(raw,"/v1/media/") {
   var ok bool
   err:=db.Get().QueryRowContext(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM media_assets WHERE id=$1 AND user_id=$2 AND character_image_validated AND kind='image')`,strings.TrimPrefix(raw,"/v1/media/"),c.GetString("user_id")).Scan(&ok)
   return err==nil&&ok
  };return admin && validEncounterURL(raw)
 }
 for _,image:=range item.ImageURLs { if !validImage(image) { c.JSON(400,gin.H{"error":"invalid character image"});return } }
 if item.Name == "" || utf8.RuneCountInString(item.Name)>80 || utf8.RuneCountInString(item.Persona)>4000 || utf8.RuneCountInString(item.Description)>500 || utf8.RuneCountInString(item.Personality)>200 || !validImage(item.CoverURL) || (item.AvatarURL!="" && !validImage(item.AvatarURL)) || (item.Gender!="male" && item.Gender!="female" && item.Gender!="other") {
  c.JSON(400,gin.H{"error":"invalid character fields"}); return
 }
 id := c.Param("id")
 images,_:=json.Marshal(item.ImageURLs)
 tags,_:=json.Marshal(item.Tags)
 if id != "" {
  if _,err:=uuid.Parse(id); err!=nil { c.JSON(400,gin.H{"error":"invalid character id"}); return }
  result,err:=db.Get().ExecContext(c.Request.Context(),`UPDATE encounter_characters SET name=$2,gender=$3,personality=$4,persona=$5,description=$6,cover_url=$7,avatar_url=$8,enabled=$9,sort_order=$10,image_urls=$11,age=$12,tags=$13 WHERE id=$1 AND owner_id IS NULL`,id,item.Name,item.Gender,item.Personality,item.Persona,item.Description,item.CoverURL,item.AvatarURL,item.Enabled,item.SortOrder,string(images),item.Age,string(tags))
  if err!=nil { c.JSON(500,gin.H{"error":"cannot save character"}); return }
  n,_:=result.RowsAffected(); if n!=1 { c.JSON(404,gin.H{"error":"character not found"}); return }
 } else {
  id=uuid.NewString(); var owner any
  if !admin { owner=c.GetString("user_id"); item.Enabled=true; item.SortOrder=0; item.Private=true }
  _,err:=db.Get().ExecContext(c.Request.Context(),`INSERT INTO encounter_characters(id,owner_id,name,gender,personality,persona,description,cover_url,avatar_url,enabled,sort_order,image_urls,age,tags) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`,id,owner,item.Name,item.Gender,item.Personality,item.Persona,item.Description,item.CoverURL,item.AvatarURL,item.Enabled,item.SortOrder,string(images),item.Age,string(tags))
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
func encounterOwned(c *gin.Context) bool {
 if _,err:=uuid.Parse(c.Param("id")); err!=nil { c.JSON(404,gin.H{"error":"conversation not found"}); return false }
 var exists bool
 if db.Get().QueryRowContext(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM encounter_conversations WHERE id=$1 AND user_id=$2)`,c.Param("id"),c.GetString("user_id")).Scan(&exists)!=nil || !exists { c.JSON(404,gin.H{"error":"conversation not found"}); return false }; return true
}
func GetEncounterMessages(c *gin.Context) {
 if !encounterOwned(c) { return }
 rows,err:=db.Get().QueryContext(c.Request.Context(),`SELECT id,sender_type,content,media_url,media_type FROM (SELECT m.id,m.sender_type,m.content,m.media_url,m.created_at,CASE WHEN r.product_key='encounter_video' THEN 'video' ELSE 'image' END AS media_type FROM encounter_messages m JOIN encounter_requests r ON r.id=m.request_id WHERE m.conversation_id=$1 ORDER BY m.created_at DESC,m.id DESC LIMIT 100) m ORDER BY created_at,id`,c.Param("id"))
 if err!=nil { c.JSON(500,gin.H{"error":"cannot load messages"}); return }; defer rows.Close()
 items:=[]gin.H{}
 for rows.Next() { var id,sender,content,media,kind string; if rows.Scan(&id,&sender,&content,&media,&kind)!=nil { c.JSON(500,gin.H{"error":"cannot read messages"}); return }; items=append(items,gin.H{"id":id,"sender_type":sender,"content":content,"media_url":media,"media_type":kind}) }
 if rows.Err()!=nil { c.JSON(500,gin.H{"error":"cannot read messages"}); return }; rows.Close()
 var demand,key,product string; var coins int
 err=db.Get().QueryRowContext(c.Request.Context(),`SELECT content,request_key,product_key,quoted_coins FROM encounter_requests WHERE conversation_id=$1 AND status='processing'`,c.Param("id")).Scan(&demand,&key,&product,&coins)
 var pending any
 if err==nil { pending=gin.H{"content":demand,"idempotency_key":key,"product_key":product,"quoted_coins":coins} } else if err!=sql.ErrNoRows { c.JSON(500,gin.H{"error":"cannot load pending reply"}); return }
 c.JSON(200,gin.H{"items":items,"processing_request":pending})
}

func SendEncounterMessage(c *gin.Context) {
 if !encounterOwned(c) { return }
 var input struct { Content string `json:"content"`; Key string `json:"idempotency_key"`; Product string `json:"product_key"`; Coins int `json:"quoted_coins"` }
 if c.ShouldBindJSON(&input)!=nil || strings.TrimSpace(input.Content)=="" || utf8.RuneCountInString(input.Content)>2000 || len(input.Key)>80 || input.Key=="" { c.JSON(400,gin.H{"error":"invalid message"}); return }
 ctx,cancel:=context.WithTimeout(context.WithoutCancel(c.Request.Context()),5*time.Minute); defer cancel()
 _,errRecovery:=db.Get().ExecContext(ctx,`UPDATE encounter_requests r SET status='failed' WHERE conversation_id=$1 AND status='processing' AND created_at<CURRENT_TIMESTAMP-interval '10 minutes' AND (spend_id IS NULL OR EXISTS(SELECT 1 FROM credit_spends s WHERE s.id=r.spend_id AND s.status='refunded'))`,c.Param("id"))
 if errRecovery!=nil { c.JSON(500,gin.H{"error":"cannot recover requests"}); return }
 if existingEncounterRequest(c,ctx,input.Key,input.Content,input.Product,input.Coins) { return }
 if companionAgent==nil { c.JSON(503,gin.H{"error":"model service unavailable"}); return }
 var character encounterCharacter
 err:=scanEncounter(db.Get().QueryRowContext(ctx,"SELECT "+"r.id,r.name,r.gender,r.personality,r.persona,r.description,r.cover_url,r.avatar_url,r.enabled,r.sort_order,r.image_urls,r.age,r.tags,(r.owner_id IS NOT NULL)"+` FROM encounter_characters r JOIN encounter_conversations v ON v.character_id=r.id WHERE v.id=$1 AND v.user_id=$2 AND r.enabled`,c.Param("id"),c.GetString("user_id")),&character)
 if err!=nil { c.JSON(404,gin.H{"error":"character unavailable"}); return }
 var product *credits.Product
 if input.Product!="" {
  subscribed,e:=userHasActiveSubscription(c.GetString("user_id"))
  if e!=nil { c.JSON(503,gin.H{"error":"subscription unavailable"}); return }
  if !subscribed { subscriptionRequired(c,"experience_requires_subscription","Subscribe to use this experience");return }
  products,e:=credits.ListProducts(ctx,db.Get(),currentEnvironment(),"")
  if e!=nil { c.JSON(503,gin.H{"error":"products unavailable"}); return }
  for i:=range products { if products[i].Key==input.Product { product=&products[i]; break } }
  if input.Product=="encounter_video" { product,err=loadEncounterVideo(ctx); if err!=nil || !product.Enabled || !product.IsLaunched { c.JSON(409,gin.H{"error":"video unavailable"}); return } }
  if product==nil || (product.Category!="gift" && product.Category!="photo") { c.JSON(400,gin.H{"error":"unsupported encounter product"}); return }
  if product.Coins!=input.Coins { c.JSON(409,gin.H{"code":"price_changed","error":"price changed"}); return }
  if product.Key=="encounter_video" { modelID,_:=product.Metadata["model_id"].(string); duration,_:=product.Metadata["duration"].(float64); if err:=companionAgent.CheckEncounterVideo(ctx,modelID,int(duration)); err!=nil { c.JSON(409,gin.H{"error":err.Error()}); return } }
 }
 requestID:=uuid.NewString()
 result,err:=db.Get().ExecContext(ctx,`INSERT INTO encounter_requests(id,conversation_id,request_key,content,product_key,quoted_coins) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(conversation_id,request_key) DO NOTHING`,requestID,c.Param("id"),input.Key,input.Content,input.Product,input.Coins)
 if err!=nil { if e,ok:=err.(*pq.Error); ok && e.Code=="23505" { c.JSON(409,gin.H{"code":"request_processing","error":"another reply is processing"}); return }; c.JSON(500,gin.H{"error":"cannot create request"}); return }
 n,_:=result.RowsAffected()
 if n==0 {
  if !existingEncounterRequest(c,ctx,input.Key,input.Content,input.Product,input.Coins) { c.JSON(503,gin.H{"error":"request state unavailable"}) }; return
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
  product=&spend.Product
  if _,err=db.Get().ExecContext(ctx,`UPDATE encounter_requests SET spend_id=$2 WHERE id=$1`,requestID,spend.ID); err!=nil { fail(err); return }
 }
 character.Persona=fmt.Sprintf("%s\nAge: %d. Personality: %s. Tags: %s.",character.Persona,character.Age,character.Personality,strings.Join(character.Tags,", "))
 history:=[]agent.ChatMessage{}
 rows,err:=db.Get().QueryContext(ctx,`SELECT sender_type,content FROM (SELECT sender_type,content,created_at,id FROM encounter_messages WHERE conversation_id=$1 ORDER BY created_at DESC,id DESC LIMIT 30) m ORDER BY created_at,id`,c.Param("id"))
 if err!=nil { fail(err); return }
 for rows.Next() { var sender,text string; if err=rows.Scan(&sender,&text); err!=nil { rows.Close(); fail(err); return }; if sender=="character" { sender="assistant" }; history=append(history,agent.ChatMessage{Role:sender,Content:text}) }; err=rows.Err(); rows.Close(); if err!=nil { fail(err); return }
 history=append(history,agent.ChatMessage{Role:"user",Content:input.Content})
 var reply,media,mediaRequest string
 if product!=nil && product.Key=="encounter_video" { modelID,_:=product.Metadata["model_id"].(string); duration,_:=product.Metadata["duration"].(float64); media,err=companionAgent.VideoEncounter(ctx,c.GetString("user_id"),modelID,int(duration),character.CoverURL,input.Content) } else if product!=nil && product.Category=="photo" { media,err=companionAgent.PhotoEncounter(ctx,c.GetString("user_id"),character.Name,character.Persona,character.CoverURL,input.Content) } else { var response agent.EncounterReply; response,err=companionAgent.ReplyEncounter(ctx,c.GetString("user_id"),character.Name,character.Persona,c.GetHeader("Accept-Language"),history); reply=response.Content; if product==nil && response.MediaRequest!="none" { mediaRequest=response.MediaRequest } }
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
 if err==nil { _,err=tx.ExecContext(settlement,`UPDATE encounter_requests SET status='completed',media_request=$2 WHERE id=$1`,requestID,mediaRequest) }
 if err==nil { _,err=tx.ExecContext(settlement,`UPDATE encounter_conversations SET updated_at=CURRENT_TIMESTAMP WHERE id=$1`,c.Param("id")) }
 if err!=nil { tx.Rollback(); fail(err); return }
 if err=tx.Commit(); err!=nil {
  var status string
  if db.Get().QueryRowContext(settlement,`SELECT status FROM encounter_requests WHERE id=$1`,requestID).Scan(&status)!=nil { c.JSON(503,gin.H{"error":"settlement unknown; retry original request","code":"settlement_pending"}); return }
  if status!="completed" { fail(err); return }
 }
 c.JSON(200,gin.H{"status":"completed","media_request":mediaRequest})
}

func existingEncounterRequest(c *gin.Context, ctx context.Context, requestKey, demand, product string, quoted int) bool {
 var content,key,status,mediaRequest string; var coins int
 err:=db.Get().QueryRowContext(ctx,`SELECT content,product_key,quoted_coins,status,media_request FROM encounter_requests WHERE conversation_id=$1 AND request_key=$2`,c.Param("id"),requestKey).Scan(&content,&key,&coins,&status,&mediaRequest)
 if err==sql.ErrNoRows { return false }
 if err!=nil { c.JSON(503,gin.H{"error":"cannot load request"}); return true }
 if content!=demand || key!=product || coins!=quoted { c.JSON(409,gin.H{"code":"request_mismatch","error":"request key already used"}); return true }
 if status=="completed" { c.JSON(200,gin.H{"status":status,"idempotent":true,"media_request":mediaRequest}); return true }
 c.JSON(409,gin.H{"code":"request_"+status,"error":"request "+status}); return true
}
