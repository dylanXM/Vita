package handler

import (
 "net/http"
 "github.com/gin-gonic/gin"
 "vita/internal/encounterart"
)

func EncounterArtwork(c *gin.Context) {
 data,err:=encounterart.Read(c.Param("name"));if err!=nil { c.Status(404);return }
 c.Header("Cache-Control","public, max-age=86400")
 c.Data(200,http.DetectContentType(data),data)
}
