package handler

import (
 "html/template"
 "net/url"
 "strings"
 "github.com/gin-gonic/gin"
 "github.com/google/uuid"
 "vita/internal/db"
)

var encounterShareTemplate=template.Must(template.New("encounter-share").Parse(`<!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{{.Name}} · Vita</title><meta name="description" content="{{.Description}}"></head><body style="margin:0;background:#151016;color:#fff;font:16px system-ui"><main style="max-width:480px;margin:auto;padding:24px"><img src="{{.CoverURL}}" alt="{{.Name}}" style="width:100%;border-radius:24px">{{if .AvatarURL}}<img src="{{.AvatarURL}}" alt="{{.Name}}" style="width:64px;height:64px;border-radius:50%;object-fit:cover;margin-top:16px">{{end}}<h1>{{.Name}} · {{.Age}}</h1><p>{{.Personality}}</p><p>{{range .Tags}}<span style="display:inline-block;padding:6px 12px;margin:4px;background:#33202c;border-radius:18px">{{.}}</span>{{end}}</p><p style="white-space:pre-wrap">{{.Description}}</p><p>♡ {{.Followers}}</p><footer>Vita</footer></main></body></html>`))

// Public previews never expose private characters, prompts or conversations.
func EncounterShare(c *gin.Context){
 if _,err:=uuid.Parse(c.Param("id"));err!=nil{c.Status(404);return}
 var item encounterCharacter
 if scanEncounter(db.Get().QueryRowContext(c.Request.Context(),"SELECT "+encounterColumns+" FROM encounter_characters WHERE id=$1 AND owner_id IS NULL AND enabled",c.Param("id")),&item)!=nil{c.Status(404);return}
 items:=[]encounterCharacter{item};if fillEncounterFollowers(c.Request.Context(),items,"")!=nil{c.Status(503);return};item=items[0]
 // Configured HTTP(S) covers remain absolute; bundled artwork resolves on this server.
 absolute:=func(raw string)string{if !strings.HasPrefix(raw,"/"){return raw};scheme:="http";if c.Request.TLS!=nil||strings.EqualFold(c.GetHeader("X-Forwarded-Proto"),"https"){scheme="https"};return (&url.URL{Scheme:scheme,Host:c.Request.Host,Path:raw}).String()}
 item.CoverURL=absolute(item.CoverURL);item.AvatarURL=absolute(item.AvatarURL)
 c.Header("Content-Type","text/html; charset=utf-8");c.Header("Cache-Control","no-store")
 c.Header("Content-Security-Policy","default-src 'none'; img-src https: http:; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'")
 _=encounterShareTemplate.Execute(c.Writer,item)
}
