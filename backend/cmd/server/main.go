package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/sync/errgroup"

	"vita/internal/config"
	"vita/internal/db"
	"vita/internal/handler"
	"vita/internal/middleware"
	"vita/internal/storage"
)

func main() {
	cfg := config.Load()

	dbClient, err := db.Open(cfg)
	if err != nil {
		log.Fatalf("failed to connect database: %v", err)
	}
	defer dbClient.Close()

	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisURL,
		Password: cfg.RedisPassword,
		DB:       0,
	})
	defer rdb.Close()

	store := storage.New(cfg)
	if err := store.Init(); err != nil {
		log.Fatalf("failed to init storage: %v", err)
	}

	engine := gin.Default()
	engine.Use(middleware.RequestID())
	engine.Use(middleware.CORS())
	engine.Use(middleware.RateLimit(rdb))
	engine.Use(middleware.AuthMiddleware())

	api := engine.Group("/v1")
	{
		auth := api.Group("/auth")
		{
			auth.POST("/register", handler.Register)
			auth.POST("/login", handler.Login)
			auth.POST("/logout", handler.Logout)
			auth.POST("/refresh", handler.RefreshToken)
		}

		companions := api.Group("/companions")
		{
			companions.POST("/", handler.CreateCompanion)
			companions.GET("/:id", handler.GetCompanion)
			companions.GET("/", handler.ListCompanions)
			companions.PUT("/:id", handler.UpdateCompanion)
			companions.DELETE("/:id", handler.DeleteCompanion)
		}

		conversations := api.Group("/conversations")
		{
			conversations.POST("/:id/messages", handler.SendMessage)
			conversations.GET("/:id/messages", handler.GetMessages)
		}

		life := api.Group("/companions/:id/life")
		{
			life.GET("/today", handler.GetTodayLife)
			life.GET("/events", handler.GetLifeEvents)
		}

		memories := api.Group("/companions/:id/memories")
		{
			memories.GET("/", handler.GetMemories)
		}

		media := api.Group("/media")
		{
			media.POST("/upload", handler.UploadMedia)
			media.POST("/generate", handler.GenerateMedia)
		}

		api.GET("/health", handler.Health)
	}

	srv := &http.Server{
		Addr:         cfg.HTTPAddr,
		Handler:      engine,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("server shutdown failed: %v", err)
	}

	fmt.Println("vita server stopped")
}

func init() {
	gin.SetMode(gin.ReleaseMode)
}

func jwtSecret() []byte {
	return []byte("dev-secret-change-me-32-characters-min")
}

func hashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), 14)
	return string(bytes), err
}

func verifyPassword(hash, password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

func generateToken(userID uuid.UUID) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"user_id": userID.String(),
		"exp":     time.Now().Add(24 * time.Hour).Unix(),
	})
	return token.SignedString(jwtSecret())
}
