package handler

import (
 "context"
 "database/sql"
 "strings"
 "strconv"
 "time"
 "unicode/utf8"
 "github.com/gin-gonic/gin"
 "github.com/google/uuid"
 "github.com/lib/pq"
 "vita/internal/db"
)

func fillEncounterFollowers(ctx context.Context,items []encounterCharacter,user string) error {
 if len(items)==0{return nil};ids:=[]string{};positions:=map[string]int{}
 for i,item:=range items{ids=append(ids,item.ID);positions[item.ID]=i}
 rows,err:=db.Get().QueryContext(ctx,`SELECT character_id,count(*),bool_or(user_id=$2) FROM encounter_follows WHERE character_id=ANY($1::uuid[]) GROUP BY character_id`,pq.Array(ids),user)
 if err!=nil{return err};defer rows.Close()
 for rows.Next(){var id string;var count int64;var following bool;if err:=rows.Scan(&id,&count,&following);err!=nil{return err};i:=positions[id];items[i].Followers=count;items[i].Following=following};return rows.Err()
}
func encounterSocialAccess(c *gin.Context) bool {
 if _,err:=uuid.Parse(c.Param("id"));err!=nil{c.JSON(404,gin.H{"error":"character not found"});return false}
 var exists bool
 err:=db.Get().QueryRowContext(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM encounter_characters r WHERE r.id=$1 AND (r.owner_id IS NULL OR r.owner_id=$2) AND (r.enabled OR EXISTS(SELECT 1 FROM encounter_conversations v WHERE v.character_id=r.id AND v.user_id=$2) OR EXISTS(SELECT 1 FROM encounter_follows f WHERE f.character_id=r.id AND f.user_id=$2)))`,c.Param("id"),c.GetString("user_id")).Scan(&exists)
 if err!=nil||!exists{c.JSON(404,gin.H{"error":"character unavailable"});return false};return true
}
func FollowEncounterCharacter(c *gin.Context){
 if !encounterSocialAccess(c){return};var input struct{Following *bool `json:"following"`}
 if c.ShouldBindJSON(&input)!=nil||input.Following==nil{c.JSON(400,gin.H{"error":"following required"});return}
 tx,err:=db.Get().BeginTx(c.Request.Context(),nil);if err!=nil{c.JSON(500,gin.H{"error":"follow unavailable"});return};defer tx.Rollback()
 var id string;var enabled bool
 if tx.QueryRowContext(c.Request.Context(),`SELECT id,enabled FROM encounter_characters WHERE id=$1 FOR UPDATE`,c.Param("id")).Scan(&id,&enabled)!=nil{c.JSON(404,gin.H{"error":"character unavailable"});return}
 if *input.Following&&!enabled{c.JSON(409,gin.H{"error":"character unavailable"});return}
 if *input.Following{_,err=tx.ExecContext(c.Request.Context(),`INSERT INTO encounter_follows(user_id,character_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,c.GetString("user_id"),id)}else{_,err=tx.ExecContext(c.Request.Context(),`DELETE FROM encounter_follows WHERE user_id=$1 AND character_id=$2`,c.GetString("user_id"),id)}
 var count int64;if err==nil{err=tx.QueryRowContext(c.Request.Context(),`SELECT count(*) FROM encounter_follows WHERE character_id=$1`,id).Scan(&count)}
 if err!=nil{c.JSON(500,gin.H{"error":"cannot update follow"});return};if tx.Commit()!=nil{c.JSON(503,gin.H{"error":"follow uncertain; retry same state"});return}
 c.JSON(200,gin.H{"follower_count":count,"is_following":*input.Following})
}

func GetEncounterCharacter(c *gin.Context){
 if !encounterSocialAccess(c){return};var item encounterCharacter
 if scanEncounter(db.Get().QueryRowContext(c.Request.Context(),"SELECT "+encounterColumns+" FROM encounter_characters WHERE id=$1",c.Param("id")),&item)!=nil{c.JSON(404,gin.H{"error":"character unavailable"});return}
 items:=[]encounterCharacter{item};if fillEncounterFollowers(c.Request.Context(),items,c.GetString("user_id"))!=nil{c.JSON(503,gin.H{"error":"followers unavailable"});return};item=items[0];item.Persona="";c.JSON(200,item)
}
func ReportEncounterCharacter(c *gin.Context){
 if !encounterSocialAccess(c){return}
 var input struct{Reason string `json:"reason"`;Details string `json:"details"`;Contact string `json:"contact"`;Key string `json:"idempotency_key"`}
 if c.ShouldBindJSON(&input)!=nil{c.JSON(400,gin.H{"error":"invalid report"});return}
 input.Details=strings.TrimSpace(input.Details);input.Contact=strings.TrimSpace(input.Contact)
 reasons:=map[string]bool{"inappropriate":true,"harassment":true,"misleading":true,"other":true}
 if !reasons[input.Reason]||utf8.RuneCountInString(input.Details)<10||utf8.RuneCountInString(input.Details)>2000||utf8.RuneCountInString(input.Contact)>200||input.Key==""||len(input.Key)>80{c.JSON(400,gin.H{"error":"reason and 10–2000 characters of details required"});return}
 var id string
 err:=db.Get().QueryRowContext(c.Request.Context(),`INSERT INTO encounter_reports(id,user_id,character_id,request_key,reason,details,contact) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(user_id,character_id,request_key) DO UPDATE SET request_key=encounter_reports.request_key WHERE encounter_reports.reason=EXCLUDED.reason AND encounter_reports.details=EXCLUDED.details AND encounter_reports.contact=EXCLUDED.contact RETURNING id`,uuid.NewString(),c.GetString("user_id"),c.Param("id"),input.Key,input.Reason,input.Details,input.Contact).Scan(&id)
 if err==sql.ErrNoRows{c.JSON(409,gin.H{"error":"report key already used"});return};if err!=nil{c.JSON(500,gin.H{"error":"cannot save report"});return}
 c.JSON(200,gin.H{"id":id,"status":"received"})
}
func AdminEncounterReports(c *gin.Context){
 page,_:=strconv.Atoi(c.DefaultQuery("page","1"));if page<1{page=1};if page>10000{page=10000};offset:=(page-1)*50
 rows,err:=db.Get().QueryContext(c.Request.Context(),`SELECT q.id,q.character_id,r.name,q.user_id,COALESCE(u.email,''),q.reason,q.details,q.contact,q.status,q.review_note,q.created_at,q.reviewed_at,COALESCE(q.reviewed_by,'') FROM encounter_reports q JOIN encounter_characters r ON r.id=q.character_id JOIN users u ON u.id=q.user_id ORDER BY q.created_at DESC,q.id LIMIT 51 OFFSET $1`,offset)
 if err!=nil{c.JSON(500,gin.H{"error":"reports unavailable"});return};defer rows.Close();items:=[]gin.H{}
 for rows.Next(){var id,char,name,user,email,reason,details,contact,status,note,reviewer string;var created time.Time;var reviewed sql.NullTime
 if rows.Scan(&id,&char,&name,&user,&email,&reason,&details,&contact,&status,&note,&created,&reviewed,&reviewer)!=nil{c.JSON(500,gin.H{"error":"cannot read reports"});return}
 var reviewTime any;if reviewed.Valid{reviewTime=reviewed.Time}
 items=append(items,gin.H{"id":id,"character_id":char,"character_name":name,"user_id":user,"email":email,"reason":reason,"details":details,"contact":contact,"status":status,"review_note":note,"created_at":created,"reviewed_at":reviewTime,"reviewed_by":reviewer})}
 if rows.Err()!=nil{c.JSON(500,gin.H{"error":"cannot read reports"});return};more:=len(items)>50;if more{items=items[:50]};c.JSON(200,gin.H{"items":items,"has_more":more})
}
func AdminReviewEncounterReport(c *gin.Context){
 if _,err:=uuid.Parse(c.Param("id"));err!=nil{c.JSON(400,gin.H{"error":"invalid report id"});return}
 var input struct{Status string `json:"status"`;Note string `json:"review_note"`}
 if c.ShouldBindJSON(&input)!=nil||(input.Status!="valid"&&input.Status!="dismissed"&&input.Status!="pending")||utf8.RuneCountInString(strings.TrimSpace(input.Note))<2||utf8.RuneCountInString(input.Note)>2000{c.JSON(400,gin.H{"error":"status and review note required"});return}
 result,err:=db.Get().ExecContext(c.Request.Context(),`UPDATE encounter_reports SET status=$2,review_note=$3,reviewed_by=$4,reviewed_at=CURRENT_TIMESTAMP WHERE id=$1`,c.Param("id"),input.Status,strings.TrimSpace(input.Note),c.GetString("user_id"))
 if err!=nil{c.JSON(500,gin.H{"error":"cannot review report"});return};n,_:=result.RowsAffected();if n!=1{c.JSON(404,gin.H{"error":"report not found"});return};c.JSON(200,gin.H{"status":input.Status})
}

func AdminEncounterCharacterStatus(c *gin.Context){
 if _,err:=uuid.Parse(c.Param("id"));err!=nil{c.JSON(400,gin.H{"error":"invalid character id"});return}
 var input struct{Enabled *bool `json:"enabled"`};if c.ShouldBindJSON(&input)!=nil||input.Enabled==nil{c.JSON(400,gin.H{"error":"enabled required"});return}
 result,err:=db.Get().ExecContext(c.Request.Context(),`UPDATE encounter_characters SET enabled=$2 WHERE id=$1`,c.Param("id"),*input.Enabled)
 if err!=nil{c.JSON(500,gin.H{"error":"cannot update status"});return};n,_:=result.RowsAffected();if n!=1{c.JSON(404,gin.H{"error":"character not found"});return};c.JSON(200,gin.H{"enabled":*input.Enabled})
}
