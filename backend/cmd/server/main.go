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

	"vita/internal/agent"
	"vita/internal/auth"
	"vita/internal/config"
	"vita/internal/credits"
	"vita/internal/db"
	"vita/internal/handler"
	"vita/internal/mail"
	"vita/internal/middleware"
	"vita/internal/storage"
)

func main() {
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		log.Fatalf("invalid configuration: %v", err)
	}
	fmt.Printf("vita server starting in environment: %s\n", cfg.Env)
	tokenManager, err := auth.NewTokenManager(cfg.JWTSecret, cfg.JWTTTL, cfg.JWTRefreshTTL)
	if err != nil {
		log.Fatalf("failed to initialize authentication: %v", err)
	}
	redisClient, err := handler.InitRedis(cfg.RedisURL, cfg.RedisPassword)
	if err != nil {
		log.Fatalf("failed to connect Redis: %v", err)
	}
	defer redisClient.Close()
	handler.InitAuth(tokenManager)

	dbClient, err := db.Open(cfg)
	if err != nil {
		log.Fatalf("failed to connect database: %v", err)
	}
	defer dbClient.Close()
	mediaStorage, err := storage.NewService(dbClient, config.EnvProd, cfg.AgentConfigKey)
	if err != nil {
		log.Fatalf("failed to initialize media storage: %v", err)
	}
	handler.InitMediaStorage(mediaStorage)
	handler.InitAdminImageBaseURL(cfg.PublicAPIBaseURL)

	pushClient, err := agent.NewFCMClient(cfg.FirebaseProjectID, cfg.FirebaseServiceAccountBase64)
	if err != nil {
		log.Fatalf("failed to initialize device push: %v", err)
	}
	agentService, err := agent.NewService(dbClient, cfg.AgentConfigKey, cfg.MockGeneration, pushClient)
	if err != nil {
		log.Fatalf("failed to initialize companion agent: %v", err)
	}
	agentService.SetMediaStorage(mediaStorage)
	handler.InitAgent(agentService)
	agentCtx, stopAgent := context.WithCancel(context.Background())
	defer stopAgent()
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-agentCtx.Done():
				return
			case <-ticker.C:
				if err := credits.RefundStale(agentCtx, dbClient, 10*time.Minute); err != nil {
					log.Printf("credit reservation recovery: %v", err)
				}
				if err := handler.PurgeExpiredCompanions(agentCtx); err != nil {
					log.Printf("expired companion cleanup: %v", err)
				}
				if err := mediaStorage.ProcessDeletionQueue(agentCtx, 50); err != nil {
					log.Printf("media object cleanup: %v", err)
				}
			}
		}
	}()
	if cfg.AgentEnabled {
		go agentService.Run(agentCtx, cfg.AgentTick)
	}

	// The stamped environment must be set before any request creates an account.

	// Seeding needs the schema, so it runs after Open() has migrated.
	if err := db.EnsureAdmin(cfg.AdminEmail, cfg.AdminPassword, cfg.AdminEmails, config.EnvProd); err != nil {
		log.Fatalf("failed to seed administrator account: %v", err)
	}

	// Billing + Google sign-in configuration (set before any request arrives).
	handler.InitBilling(handler.BillingConfig{
		RevenueCatWebhookSecret:    cfg.RevenueCatWebhookSecret,
		StripeSecretKey:            cfg.StripeSecretKey,
		StripeWebhookSecret:        cfg.StripeWebhookSecret,
		SubscriptionCreditsMonthly: cfg.SubscriptionCreditsMonthly,
	})
	go func() {
		if err := handler.GrantDueAnnualSubscriptionCredits(); err != nil {
			log.Printf("annual subscription monthly credits: %v", err)
		}
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-agentCtx.Done():
				return
			case <-ticker.C:
				if err := handler.GrantDueAnnualSubscriptionCredits(); err != nil {
					log.Printf("annual subscription monthly credits: %v", err)
				}
			}
		}
	}()
	handler.SetGoogleClientID(cfg.GoogleClientID)

	// Verification-code email (dev: codes are printed to the server log).
	handler.InitMailer(mail.Config{
		Host:     cfg.SMTPHost,
		Port:     cfg.SMTPPort,
		Username: cfg.SMTPUsername,
		Password: cfg.SMTPPassword,
		From:     cfg.SMTPFrom,
		FromName: cfg.SMTPFromName,
	})

	engine := gin.Default()
	engine.Use(middleware.RequestID())
	engine.Use(middleware.CORS(cfg.AllowedOrigins, cfg.Env == config.EnvDev))
	engine.Use(middleware.AuthMiddleware(tokenManager, redisClient))

	api := engine.Group("/v1")
	{
		auth := api.Group("/auth")
		{
			auth.Use(middleware.RateLimit(20, time.Minute))
			auth.POST("/send-code", handler.SendCode)
			auth.POST("/login", handler.Login)
			auth.POST("/admin/login", handler.AdminLogin)
			auth.POST("/app/login", handler.AppLogin)
			auth.POST("/app/register", handler.AppRegister)
			auth.POST("/app/register/verify", handler.AppRegisterVerify)
			auth.POST("/webapp/login", handler.WebappLogin)
			auth.POST("/google", handler.GoogleLogin)
			auth.POST("/logout", middleware.RequireAuth(), handler.Logout)
			auth.POST("/refresh", handler.RefreshToken)
		}

		companions := api.Group("/companions")
		{
			companions.Use(middleware.RequireAuth())
			companions.POST("/", handler.CreateCompanion)
			companions.GET("/:id", handler.GetCompanion)
			companions.GET("/", handler.ListCompanions)
			companions.PUT("/:id", handler.UpdateCompanion)
			companions.DELETE("/:id", handler.DeleteCompanion)
			companions.POST("/:id/restore", handler.RestoreCompanion)
			companions.GET("/:id/experiences", handler.ListCompanionExperiences)
			companions.GET("/:id/story", handler.GetCompanionStory)
			companions.POST("/:id/experiences/:product_key", handler.PurchaseCompanionExperience)
			companions.GET("/:id/moments/:event_id", handler.GetCompanionMoment)
			companions.POST("/:id/moments/:event_id/prepare", handler.PrepareCompanionMoment)
			companions.POST("/:id/moments/:event_id/start", handler.StartCompanionMoment)
			companions.POST("/:id/moments/:event_id/finish", handler.FinishCompanionMoment)
			companions.PUT("/:id/moments/:event_id/artifact", handler.SaveCompanionMomentArtifact)
			companions.POST("/:id/transfers", middleware.RateLimit(10, time.Minute), handler.TransferToCompanion)
		}
		api.GET("/companions-deleted", middleware.RequireAuth(), handler.ListDeletedCompanions)
		api.GET("/companion-options", middleware.RequireAuth(), handler.CompanionOptions)
		api.POST("/companion-drafts", middleware.RequireAuth(), handler.GenerateCompanionDraft)
		api.POST("/me/push-tokens", middleware.RequireAuth(), handler.RegisterPushToken)
		api.DELETE("/me/push-tokens", middleware.RequireAuth(), handler.UnregisterPushToken)

		conversations := api.Group("/conversations")
		{
			conversations.Use(middleware.RequireAuth())
			conversations.POST("/", handler.GetOrCreateConversation)
			conversations.POST("/:id/messages", handler.SendMessage)
			conversations.GET("/:id/messages", handler.GetMessages)
			conversations.GET("/:id/reply-status", handler.GetReplyStatus)
			conversations.POST("/:id/reply-status/retry", handler.RetryReply)
			conversations.GET("/:id/media", handler.GetConversationMedia)
		}

		// Billing — credits, subscriptions and provider webhooks.
		api.GET("/me/credits", middleware.RequireAuth(), handler.GetCredits)
		api.GET("/ads/config", middleware.RequireAuth(), handler.GetAdmobConfig)
		api.POST("/ads/reward-sessions", middleware.RequireAuth(), handler.CreateAdmobRewardSession)
		api.POST("/credits/consume", middleware.RequireAuth(), handler.ConsumeCredits)
		api.GET("/me/subscription", middleware.RequireAuth(), handler.GetMySubscription)
		api.GET("/subscription-plans/benefits", middleware.RequireAuth(), handler.ListSubscriptionPlanBenefits)
		api.POST("/stripe/checkout", middleware.RequireAuth(), handler.CreateStripeCheckout)
		api.POST("/webhooks/revenuecat", handler.RevenueCatWebhook)
		api.POST("/webhooks/stripe", handler.StripeWebhook)
		api.GET("/webhooks/admob/reward", handler.AdmobRewardCallback)

		life := api.Group("/companions/:id/life")
		{
			life.Use(middleware.RequireAuth())
			life.GET("/today", handler.GetTodayLife)
			life.GET("/events", handler.GetLifeEvents)
			life.GET("/events/:event_id", handler.GetLifeEvent)
		}
		world := api.Group("/companions/:id/world", middleware.RequireAuth())
		{
			world.GET("/scene", handler.GetWorldScene)
			world.POST("/visit", handler.VisitWorld)
		}

		memories := api.Group("/companions/:id/memories")
		{
			memories.Use(middleware.RequireAuth())
			memories.GET("/", handler.GetMemories)
			memories.PUT("/:memory_id", handler.UpdateMemory)
			memories.PUT("/:memory_id/favorite", handler.SetMemoryFavorite)
			memories.DELETE("/:memory_id", handler.DeleteMemory)
		}
		api.GET("/journey", middleware.RequireAuth(), handler.GetJourney)
		api.GET("/explore/posts", middleware.RequireAuth(), handler.GetExplorePosts)
		aiPets := api.Group("/ai-pets", middleware.RequireAuth())
		{
			aiPets.GET("/breeds", handler.ListAIPetBreeds)
			aiPets.POST("/adopt", handler.AdoptAIPet)
			aiPets.GET("/:id/state", handler.GetAIPetState)
			aiPets.POST("/:id/feed", handler.FeedAIPet)
			aiPets.POST("/:id/care", handler.CareForAIPet)
		}
		stories := api.Group("/stories", middleware.RequireAuth())
		{
			stories.GET("/catalog", handler.ListStoryCatalog)
			stories.GET("/", handler.ListStories)
			stories.POST("/", handler.StartStory)
			stories.GET("/:id", handler.GetStory)
			stories.POST("/:id/choices", handler.AdvanceStory)
			stories.POST("/:id/storyboards", handler.GenerateStoryBoard)
		}
		api.POST("/story-backgrounds", middleware.RequireAuth(), handler.CreateStoryBackground)
		api.DELETE("/story-backgrounds/:id", middleware.RequireAuth(), handler.DeleteStoryBackground)

		media := api.Group("/media")
		{
			media.POST("/upload", middleware.RequireAuth(), handler.UploadMedia)
			media.POST("/generate", middleware.RequireAuth(), handler.GenerateMedia)
			media.GET("/:id", middleware.RequireAuth(), handler.GetMedia)
		}
		api.GET("/admin-images/:id", handler.GetAdminImage)

		api.GET("/health", handler.Health)
		api.GET("/app-content", handler.AppContent)
		api.POST("/events", middleware.RateLimit(120, time.Minute), handler.IngestAnalyticsEvents)

		// Current account — used by the admin dashboard to rehydrate a stored
		// session and to verify the account has the admin role.
		api.GET("/me", middleware.RequireAuth(), handler.Me)
		api.PUT("/me/locale", middleware.RequireAuth(), handler.UpdateMyLocale)
		api.PUT("/me/profile", middleware.RequireAuth(), handler.UpdateMyProfile)
		api.GET("/me/world-preferences", middleware.RequireAuth(), handler.GetWorldPreferences)
		api.PUT("/me/world-preferences", middleware.RequireAuth(), handler.UpdateWorldPreferences)
		api.DELETE("/me", middleware.RequireAuth(), handler.DeleteMe)

		admin := api.Group("/admin", middleware.RequireAdmin())
		{
			admin.POST("/images", handler.AdminUploadImage)
			admin.GET("/stats", handler.AdminStats)
			admin.GET("/product-metrics", handler.AdminProductMetrics)
			admin.GET("/storage-config", handler.AdminGetStorageConfig)
			admin.PUT("/storage-config", handler.AdminUpdateStorageConfig)
			admin.POST("/storage-config/test", handler.AdminTestStorageConfig)
			admin.GET("/subscription-plans", handler.AdminListSubscriptionPlans)
			admin.POST("/subscription-plans", handler.AdminCreateSubscriptionPlan)
			admin.PUT("/subscription-plans/:id", handler.AdminUpdateSubscriptionPlan)
			admin.DELETE("/subscription-plans/:id", handler.AdminDeleteSubscriptionPlan)
			admin.GET("/coin-packs", handler.AdminListCoinPacks)
			admin.POST("/coin-packs", handler.AdminCreateCoinPack)
			admin.PUT("/coin-packs/:id", handler.AdminUpdateCoinPack)
			admin.DELETE("/coin-packs/:id", handler.AdminDeleteCoinPack)
			admin.GET("/purchases", handler.AdminListPurchases)
			admin.GET("/credit-ledger", handler.AdminListCreditLedger)
			admin.GET("/credit-products", handler.AdminListCreditProducts)
			admin.PUT("/credit-products/:product_key", handler.AdminUpdateCreditProduct)
			admin.GET("/invitation-settings", handler.AdminGetInvitationSettings)
			admin.PUT("/invitation-settings", handler.AdminUpdateInvitationSettings)
			admin.GET("/admob-settings", handler.AdminGetAdmobSettings)
			admin.PUT("/admob-settings", handler.AdminUpdateAdmobSettings)
			admin.GET("/onboarding", handler.AdminGetOnboarding)
			admin.PUT("/onboarding", handler.AdminUpdateOnboarding)
			admin.GET("/whats-new", handler.AdminListWhatsNew)
			admin.POST("/whats-new", handler.AdminCreateWhatsNew)
			admin.PUT("/whats-new/:id", handler.AdminUpdateWhatsNew)
			admin.DELETE("/whats-new/:id", handler.AdminDeleteWhatsNew)
			admin.GET("/social-links", handler.AdminGetSocialMediaLinks)
			admin.PUT("/social-links", handler.AdminUpdateSocialMediaLinks)
			admin.GET("/legal-documents", handler.AdminListLegalDocuments)
			admin.POST("/legal-documents", handler.AdminCreateLegalDocument)
			admin.PUT("/legal-documents/:id", handler.AdminUpdateLegalDocument)
			admin.POST("/legal-documents/:id/activate", handler.AdminActivateLegalDocument)
			admin.DELETE("/legal-documents/:id", handler.AdminDeleteLegalDocument)
			admin.GET("/ai-pet-breeds", handler.AdminListAIPetBreeds)
			admin.POST("/ai-pet-breeds", handler.AdminCreateAIPetBreed)
			admin.PUT("/ai-pet-breeds/:id", handler.AdminUpdateAIPetBreed)
			admin.DELETE("/ai-pet-breeds/:id", handler.AdminDeleteAIPetBreed)
			admin.GET("/story-config", handler.AdminGetStoryConfig)
			admin.PUT("/story-config", handler.AdminUpdateStoryConfig)
			admin.GET("/story-backgrounds", handler.AdminListStoryBackgrounds)
			admin.POST("/story-backgrounds", handler.AdminCreateStoryBackground)
			admin.PUT("/story-backgrounds/:id", handler.AdminUpdateStoryBackground)
			admin.DELETE("/story-backgrounds/:id", handler.AdminDeleteStoryBackground)

			users := admin.Group("/users")
			{
				users.GET("/", handler.AdminListUsers)
				users.POST("/", handler.AdminCreateUser)
				users.GET("/:id", handler.AdminGetUser)
				users.PUT("/:id", handler.AdminUpdateUser)
				users.DELETE("/:id", handler.AdminDeleteUser)
				users.POST("/:id/ban", func(c *gin.Context) { handler.AdminSetBanned(c, true) })
				users.POST("/:id/unban", func(c *gin.Context) { handler.AdminSetBanned(c, false) })
				users.GET("/:id/grant-operations", handler.AdminListGrantOperations)
				users.GET("/:id/timeline", handler.AdminUserTimeline)
				users.POST("/:id/grant-coins", handler.AdminGrantCoins)
				users.POST("/:id/grant-subscription", handler.AdminGrantSubscription)
			}

			adminCompanions := admin.Group("/companions")
			{
				adminCompanions.GET("/", handler.AdminListManagedCompanions)
				adminCompanions.GET("/:id", handler.AdminGetManagedCompanion)
				adminCompanions.PUT("/:id", handler.AdminUpdateManagedCompanion)
				adminCompanions.DELETE("/:id", handler.AdminDeleteManagedCompanion)
				adminCompanions.GET("/:id/conversations", handler.AdminListCompanionConversations)
				adminCompanions.GET("/:id/conversations/:conversation_id/messages", handler.AdminListConversationMessages)
			}

			agentAdmin := admin.Group("/agent")
			{
				agentAdmin.GET("/config", handler.AdminAgentConfig)
				agentAdmin.PUT("/settings", handler.AdminUpdateAgentSettings)
				agentAdmin.POST("/providers", handler.AdminCreateProvider)
				agentAdmin.POST("/providers/test-connection", handler.AdminTestProviderConnection)
				agentAdmin.PUT("/providers/:id", handler.AdminUpdateProvider)
				agentAdmin.DELETE("/providers/:id", handler.AdminDeleteProvider)
				agentAdmin.POST("/models", handler.AdminCreateModel)
				agentAdmin.POST("/models/test", handler.AdminTestModel)
				agentAdmin.PUT("/models/:id", handler.AdminUpdateModel)
				agentAdmin.DELETE("/models/:id", handler.AdminDeleteModel)
				agentAdmin.GET("/media-routes", handler.AdminListMediaModelRoutes)
				agentAdmin.PUT("/media-routes", handler.AdminUpdateMediaModelRoutes)
				agentAdmin.POST("/portraits", handler.AdminCreatePortrait)
				agentAdmin.PUT("/portraits/:id", handler.AdminUpdatePortrait)
				agentAdmin.GET("/companions", handler.AdminListCompanions)
				agentAdmin.POST("/companions", handler.AdminCreateCompanion)

				lifeEngine := admin.Group("/life-engine")
				{
					lifeEngine.GET("/overview", handler.AdminLifeEngineOverview)
					lifeEngine.GET("/companions", handler.AdminLifeEngineCompanions)
					lifeEngine.GET("/companions/:id/events", handler.AdminLifeEngineCompanionEvents)
					lifeEngine.POST("/companions/:id/events", handler.AdminLifeEngineCreateEvent)
					lifeEngine.PUT("/events/:eventId", handler.AdminLifeEngineUpdateEvent)
					lifeEngine.DELETE("/events/:eventId", handler.AdminLifeEngineDeleteEvent)
					lifeEngine.POST("/companions/:id/takeover", handler.AdminLifeEngineEnterTakeover)
					lifeEngine.DELETE("/companions/:id/takeover", handler.AdminLifeEngineExitTakeover)
					lifeEngine.POST("/trigger-plan", handler.AdminLifeEngineTriggerPlan)
					lifeEngine.POST("/trigger-proactive", handler.AdminLifeEngineTriggerProactive)
					lifeEngine.POST("/companions/:id/resend-outbox", handler.AdminLifeEngineResendOutbox)
					lifeEngine.POST("/companions/:id/broadcast", handler.AdminLifeEngineBroadcast)
					lifeEngine.GET("/places", handler.AdminWorldPlaces)
					lifeEngine.PUT("/places/:kind", handler.AdminUpdateWorldPlace)
					lifeEngine.GET("/campaigns", handler.AdminWorldCampaigns)
					lifeEngine.POST("/campaigns", handler.AdminSaveWorldCampaign)
					lifeEngine.PUT("/campaigns/:id", handler.AdminSaveWorldCampaign)
					lifeEngine.DELETE("/campaigns/:id", handler.AdminDeleteWorldCampaign)
				}
				agentAdmin.PUT("/companions/:id", handler.AdminUpdateCompanion)
			}
		}
	}

	srv := &http.Server{
		Addr: cfg.HTTPAddr,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodPost && (r.URL.Path == "/v1/admin/life-engine/trigger-plan" || r.URL.Path == "/v1/admin/life-engine/trigger-proactive") {
				// These passes have a 120s work budget. Allow cleanup and the JSON
				// response to finish without changing other endpoints' deadlines.
				if err := http.NewResponseController(w).SetWriteDeadline(time.Now().Add(140 * time.Second)); err != nil {
					log.Printf("set life engine response deadline: %v", err)
				}
			}
			engine.ServeHTTP(w, r)
		}),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 60 * time.Second,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	stopAgent()

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
