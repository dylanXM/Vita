package handler

import (
	"github.com/gin-gonic/gin"
	"strings"
	"vita/internal/db"
)

// Display quantities and enabled product IDs come from Backend; store prices
// and purchase authorization remain with RevenueCat and the existing handlers.
func AppBillingCatalog(c *gin.Context) {
	platform := billingCatalogPlatform(strings.ToLower(strings.TrimSpace(c.GetHeader("X-Vita-Platform"))))
	if !validBillingCatalogPlatform(platform) {
		c.JSON(400, gin.H{"error": "invalid platform"})
		return
	}
	rows, err := db.Get().QueryContext(c.Request.Context(), `SELECT 'coin',product_id,coins FROM coin_packs WHERE environment=$1 AND platform=$2 AND enabled=true AND product_id<>'' UNION ALL SELECT 'subscription',product_id,0 FROM subscription_plans WHERE environment=$1 AND platform=$2 AND enabled=true AND product_id<>''`, currentEnvironment(), platform)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to load billing catalog"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var kind, id string
		var coins int
		if err := rows.Scan(&kind, &id, &coins); err != nil {
			c.JSON(500, gin.H{"error": "failed to read billing catalog"})
			return
		}
		items = append(items, gin.H{"kind": kind, "product_id": id, "coins": coins})
	}
	if rows.Err() != nil {
		c.JSON(500, gin.H{"error": "failed to read billing catalog"})
		return
	}
	c.JSON(200, gin.H{"items": items})
}
