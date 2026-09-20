package handler

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lib/pq"

	"vita/internal/config"
	"vita/internal/db"
)

type adminProduct struct {
	ID          string    `json:"id"`
	Key         string    `json:"key"`
	Name        string    `json:"name"`
	Environment string    `json:"environment"`
	Platform    string    `json:"platform"`
	Coins       int       `json:"coins"`
	PriceUSD    float64   `json:"price_usd"`
	Period      string    `json:"period,omitempty"`
	ProductID   string    `json:"product_id"`
	Popular     bool      `json:"popular,omitempty"`
	Enabled     bool      `json:"enabled"`
	SortOrder   int       `json:"sort_order"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

func validBillingPlatform(value string) bool {
	return value == "ios" || value == "android" || value == "web"
}

func adminBillingEnvironment(c *gin.Context) (string, bool) {
	environment := strings.TrimSpace(c.Query("environment"))
	if environment == "" {
		environment = currentEnvironment()
	}
	if !config.IsValidEnvironment(environment) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "environment must be dev, beta, or prod"})
		return "", false
	}
	return environment, true
}

func validateAdminProduct(c *gin.Context, item *adminProduct, plan bool) bool {
	item.Key = strings.TrimSpace(item.Key)
	item.Name = strings.TrimSpace(item.Name)
	item.Platform = strings.ToLower(strings.TrimSpace(item.Platform))
	item.ProductID = strings.TrimSpace(item.ProductID)
	if item.Environment == "" {
		item.Environment = currentEnvironment()
	}
	if item.Key == "" || item.Name == "" || !config.IsValidEnvironment(item.Environment) ||
		!validBillingPlatform(item.Platform) || item.Coins < 0 || item.PriceUSD < 0 || item.SortOrder < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid product configuration"})
		return false
	}
	if plan {
		if item.Period != "week" && item.Period != "month" && item.Period != "year" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "period must be week, month, or year"})
			return false
		}
	} else if item.Coins < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "coins must be greater than zero"})
		return false
	}
	return true
}

func AdminListSubscriptionPlans(c *gin.Context) {
	environment, ok := adminBillingEnvironment(c)
	if !ok {
		return
	}
	platform := strings.ToLower(strings.TrimSpace(c.Query("platform")))
	query := `SELECT id, key, name, environment, platform, coins_granted, price_usd, period,
	                 product_id, enabled, sort_order, created_at, updated_at
	          FROM subscription_plans WHERE environment = $1`
	args := []any{environment}
	if platform != "" {
		if !validBillingPlatform(platform) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "platform must be ios, android, or web"})
			return
		}
		query += ` AND platform = $2`
		args = append(args, platform)
	}
	query += ` ORDER BY sort_order, price_usd, key`
	rows, err := db.Get().Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load subscription plans"})
		return
	}
	defer rows.Close()
	items := []adminProduct{}
	for rows.Next() {
		var item adminProduct
		if err := rows.Scan(&item.ID, &item.Key, &item.Name, &item.Environment, &item.Platform,
			&item.Coins, &item.PriceUSD, &item.Period, &item.ProductID, &item.Enabled,
			&item.SortOrder, &item.CreatedAt, &item.UpdatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan subscription plans"})
			return
		}
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func AdminCreateSubscriptionPlan(c *gin.Context) { adminSaveProduct(c, true, false) }
func AdminUpdateSubscriptionPlan(c *gin.Context) { adminSaveProduct(c, true, true) }
func AdminCreateCoinPack(c *gin.Context)         { adminSaveProduct(c, false, false) }
func AdminUpdateCoinPack(c *gin.Context)         { adminSaveProduct(c, false, true) }

func adminSaveProduct(c *gin.Context, plan, update bool) {
	var item adminProduct
	if err := c.ShouldBindJSON(&item); err != nil || !validateAdminProduct(c, &item, plan) {
		return
	}
	if update {
		item.ID = c.Param("id")
		if item.ID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing product id"})
			return
		}
	} else {
		item.ID = uuid.New().String()
	}

	var err error
	if plan {
		if update {
			_, err = db.Get().Exec(`UPDATE subscription_plans SET key=$1, name=$2, environment=$3, platform=$4,
				coins_granted=$5, price_usd=$6, period=$7, product_id=$8, enabled=$9, sort_order=$10,
				updated_at=CURRENT_TIMESTAMP WHERE id=$11`, item.Key, item.Name, item.Environment, item.Platform,
				item.Coins, item.PriceUSD, item.Period, item.ProductID, item.Enabled, item.SortOrder, item.ID)
		} else {
			_, err = db.Get().Exec(`INSERT INTO subscription_plans
				(id,key,name,environment,platform,coins_granted,price_usd,period,product_id,enabled,sort_order)
				VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, item.ID, item.Key, item.Name,
				item.Environment, item.Platform, item.Coins, item.PriceUSD, item.Period, item.ProductID,
				item.Enabled, item.SortOrder)
		}
	} else {
		if update {
			_, err = db.Get().Exec(`UPDATE coin_packs SET key=$1, name=$2, environment=$3, platform=$4,
				coins=$5, price_usd=$6, product_id=$7, popular=$8, enabled=$9, sort_order=$10,
				updated_at=CURRENT_TIMESTAMP WHERE id=$11`, item.Key, item.Name, item.Environment, item.Platform,
				item.Coins, item.PriceUSD, item.ProductID, item.Popular, item.Enabled, item.SortOrder, item.ID)
		} else {
			_, err = db.Get().Exec(`INSERT INTO coin_packs
				(id,key,name,environment,platform,coins,price_usd,product_id,popular,enabled,sort_order)
				VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, item.ID, item.Key, item.Name,
				item.Environment, item.Platform, item.Coins, item.PriceUSD, item.ProductID,
				item.Popular, item.Enabled, item.SortOrder)
		}
	}
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			c.JSON(http.StatusConflict, gin.H{"error": "the key or store product id already exists for this environment and platform"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save product"})
		return
	}
	c.JSON(http.StatusOK, item)
}

func AdminDeleteSubscriptionPlan(c *gin.Context) { adminDeleteProduct(c, "subscription_plans") }
func AdminDeleteCoinPack(c *gin.Context)         { adminDeleteProduct(c, "coin_packs") }

func adminDeleteProduct(c *gin.Context, table string) {
	result, err := db.Get().Exec(`DELETE FROM `+table+` WHERE id = $1`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete product"})
		return
	}
	count, _ := result.RowsAffected()
	if count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "product not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

func AdminListCoinPacks(c *gin.Context) {
	environment, ok := adminBillingEnvironment(c)
	if !ok {
		return
	}
	platform := strings.ToLower(strings.TrimSpace(c.Query("platform")))
	query := `SELECT id, key, name, environment, platform, coins, price_usd, product_id,
	                 popular, enabled, sort_order, created_at, updated_at
	          FROM coin_packs WHERE environment = $1`
	args := []any{environment}
	if platform != "" {
		if !validBillingPlatform(platform) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "platform must be ios, android, or web"})
			return
		}
		query += ` AND platform = $2`
		args = append(args, platform)
	}
	query += ` ORDER BY sort_order, price_usd, key`
	rows, err := db.Get().Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load coin packs"})
		return
	}
	defer rows.Close()
	items := []adminProduct{}
	for rows.Next() {
		var item adminProduct
		if err := rows.Scan(&item.ID, &item.Key, &item.Name, &item.Environment, &item.Platform,
			&item.Coins, &item.PriceUSD, &item.ProductID, &item.Popular, &item.Enabled,
			&item.SortOrder, &item.CreatedAt, &item.UpdatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan coin packs"})
			return
		}
		items = append(items, item)
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func adminPage(c *gin.Context) (int, int) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	return page, pageSize
}

func appendScopeFilters(c *gin.Context, where []string, args []any, platformColumn, environmentColumn string) ([]string, []any, bool) {
	environment, ok := adminBillingEnvironment(c)
	if !ok {
		return nil, nil, false
	}
	args = append(args, environment)
	where = append(where, environmentColumn+" = $"+strconv.Itoa(len(args)))
	if platform := strings.ToLower(strings.TrimSpace(c.Query("platform"))); platform != "" {
		if !validBillingPlatform(platform) && platform != "system" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid platform"})
			return nil, nil, false
		}
		args = append(args, platform)
		where = append(where, platformColumn+" = $"+strconv.Itoa(len(args)))
	}
	return where, args, true
}

func AdminListPurchases(c *gin.Context) {
	page, pageSize := adminPage(c)
	where, args, ok := appendScopeFilters(c, nil, nil, "p.platform", "p.environment")
	if !ok {
		return
	}
	condition := strings.Join(where, " AND ")
	var total int
	if err := db.Get().QueryRow(`SELECT COUNT(*) FROM billing_purchases p WHERE `+condition, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count purchases"})
		return
	}
	args = append(args, pageSize, (page-1)*pageSize)
	rows, err := db.Get().Query(`SELECT p.id,p.transaction_id,p.user_id,u.email,p.kind,p.provider,p.platform,p.environment,
		p.product_id,p.amount_minor,p.currency,p.credits,p.status,p.purchased_at
		FROM billing_purchases p JOIN users u ON u.id=p.user_id WHERE `+condition+
		` ORDER BY p.purchased_at DESC,p.id DESC LIMIT $`+strconv.Itoa(len(args)-1)+` OFFSET $`+strconv.Itoa(len(args)), args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load purchases"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id, txID, userID, email, kind, provider, platform, environment, productID, currency, status string
		var amount sql.NullInt64
		var credits int
		var purchasedAt time.Time
		if err := rows.Scan(&id, &txID, &userID, &email, &kind, &provider, &platform, &environment, &productID, &amount, &currency, &credits, &status, &purchasedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan purchases"})
			return
		}
		var amountValue any
		if amount.Valid {
			amountValue = amount.Int64
		}
		items = append(items, gin.H{"id": id, "transaction_id": txID, "user_id": userID, "user_email": email,
			"kind": kind, "provider": provider, "platform": platform, "environment": environment, "product_id": productID,
			"amount_minor": amountValue, "currency": currency, "credits": credits, "status": status, "purchased_at": purchasedAt})
	}
	adminPaged(c, items, total, page, pageSize)
}

func AdminListCreditLedger(c *gin.Context) {
	page, pageSize := adminPage(c)
	where, args, ok := appendScopeFilters(c, nil, nil, "ct.platform", "ct.environment")
	if !ok {
		return
	}
	condition := strings.Join(where, " AND ")
	var total int
	if err := db.Get().QueryRow(`SELECT COUNT(*) FROM credit_transactions ct WHERE `+condition, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count ledger entries"})
		return
	}
	args = append(args, pageSize, (page-1)*pageSize)
	rows, err := db.Get().Query(`SELECT ct.id,ct.user_id,u.email,ct.amount,ct.balance_after,ct.kind,
		COALESCE(ct.description,''),ct.platform,ct.environment,ct.created_at
		FROM credit_transactions ct JOIN users u ON u.id=ct.user_id WHERE `+condition+
		` ORDER BY ct.created_at DESC,ct.id DESC LIMIT $`+strconv.Itoa(len(args)-1)+` OFFSET $`+strconv.Itoa(len(args)), args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load ledger"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id, userID, email, kind, description, platform, environment string
		var amount, balance int
		var createdAt time.Time
		if err := rows.Scan(&id, &userID, &email, &amount, &balance, &kind, &description, &platform, &environment, &createdAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to scan ledger"})
			return
		}
		items = append(items, gin.H{"id": id, "user_id": userID, "user_email": email, "amount": amount,
			"balance_after": balance, "kind": kind, "description": description, "platform": platform,
			"environment": environment, "created_at": createdAt})
	}
	adminPaged(c, items, total, page, pageSize)
}

func adminPaged(c *gin.Context, items []gin.H, total, page, pageSize int) {
	totalPages := 0
	if total > 0 {
		totalPages = (total + pageSize - 1) / pageSize
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "total": total, "page": page, "page_size": pageSize, "total_pages": totalPages})
}
