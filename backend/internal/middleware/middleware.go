package middleware

import (
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"

	vitaauth "vita/internal/auth"
)

func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set("request_id", fmt.Sprintf("%d", time.Now().UnixNano()))
		c.Next()
	}
}

func CORS(allowedOrigins []string) gin.HandlerFunc {
	allowed := make(map[string]struct{}, len(allowedOrigins))
	for _, origin := range allowedOrigins {
		if origin = strings.TrimSpace(origin); origin != "" {
			allowed[origin] = struct{}{}
		}
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin != "" {
			if _, ok := allowed[origin]; !ok {
				c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "origin is not allowed"})
				return
			}
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
			c.Writer.Header().Set("Vary", "Origin")
		}
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Vita-Platform, X-Vita-App-Version, Accept-Language")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

func AuthMiddleware(tokens *vitaauth.TokenManager, redisClient *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.Set("user_id", "")
			c.Set("user_role", "")
			c.Next()
			return
		}

		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		if tokenString == authHeader {
			c.Set("user_id", "")
			c.Set("user_role", "")
			c.Next()
			return
		}

		claims, err := tokens.Parse(tokenString, vitaauth.TokenTypeAccess)
		if err != nil {
			c.Set("user_id", "")
			c.Set("user_role", "")
			c.Next()
			return
		}
		revoked, err := redisClient.Exists(c.Request.Context(), "vita:session:revoked:"+claims.SessionID).Result()
		if err != nil || revoked > 0 {
			c.Set("user_id", "")
			c.Set("user_role", "")
			c.Next()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("user_role", claims.Role)
		c.Set("session_id", claims.SessionID)
		c.Next()
	}
}

// RequireAuth rejects requests with no usable bearer token. AuthMiddleware runs
// first and records the parsed identity, so this only inspects what it stored.
func RequireAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetString("user_id") == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		c.Next()
	}
}

// RequireAdmin rejects requests from anyone who is not an authenticated admin.
func RequireAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetString("user_id") == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		if c.GetString("user_role") != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			return
		}
		c.Next()
	}
}

type rateLimitEntry struct {
	windowStart time.Time
	count       int
}

func RateLimit(limit int, window time.Duration) gin.HandlerFunc {
	var mu sync.Mutex
	entries := map[string]rateLimitEntry{}
	return func(c *gin.Context) {
		now := time.Now()
		key := c.ClientIP()
		mu.Lock()
		entry := entries[key]
		if entry.windowStart.IsZero() || now.Sub(entry.windowStart) >= window {
			entry = rateLimitEntry{windowStart: now}
		}
		entry.count++
		entries[key] = entry
		if len(entries) > 10000 {
			for candidate, value := range entries {
				if now.Sub(value.windowStart) >= window {
					delete(entries, candidate)
				}
			}
		}
		blocked := entry.count > limit
		mu.Unlock()
		if blocked {
			c.Header("Retry-After", fmt.Sprintf("%d", int(window.Seconds())))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "too many requests"})
			return
		}
		c.Next()
	}
}
