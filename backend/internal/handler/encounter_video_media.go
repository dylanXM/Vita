package handler

import (
 "bytes"
 "io"
 "net/http"
 "time"
 "github.com/gin-gonic/gin"
)

// Only the encounter video endpoint buffers MP4 for authenticated byte-range playback.
func EncounterVideoMedia(c *gin.Context) {
 if mediaStorage==nil { c.Status(503);return }
 media,err:=mediaStorage.Open(c.Request.Context(),c.Param("id"),c.GetString("user_id"))
 if err!=nil { c.Status(404);return };defer media.Body.Close()
 if media.MimeType!="video/mp4" || media.Size>64<<20 { c.Status(415);return }
 data,err:=io.ReadAll(io.LimitReader(media.Body,(64<<20)+1));if err!=nil||len(data)>64<<20 { c.Status(502);return }
 c.Header("Content-Type","video/mp4");c.Header("Cache-Control","private, max-age=86400")
 http.ServeContent(c.Writer,c.Request,"video.mp4",time.Time{},bytes.NewReader(data))
}
