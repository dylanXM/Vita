package handler

import (
 "github.com/gin-gonic/gin"
 "github.com/google/uuid"
 "vita/internal/db"
)

// Admin can inspect only images actually referenced by this character.
func AdminEncounterImage(c *gin.Context){
 if _,err:=uuid.Parse(c.Param("id"));err!=nil{c.Status(404);return}
 asset:=c.Param("asset");if _,err:=uuid.Parse(asset);err!=nil{c.Status(404);return}
 var owner string
 if db.Get().QueryRowContext(c.Request.Context(),`SELECT owner_id FROM encounter_characters WHERE id=$1 AND owner_id IS NOT NULL AND (avatar_url=$2 OR image_urls ? $2)`,c.Param("id"),"/v1/media/"+asset).Scan(&owner)!=nil{c.Status(404);return}
 if mediaStorage==nil{c.Status(503);return};media,err:=mediaStorage.Open(c.Request.Context(),asset,owner);if err!=nil{c.Status(404);return};defer media.Body.Close()
 c.Header("Cache-Control","no-store");c.DataFromReader(200,media.Size,media.MimeType,media.Body,nil)
}
