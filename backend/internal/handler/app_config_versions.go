package handler

import (
	"context"
	"database/sql"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"vita/internal/db"
)

type appConfigSnapshot struct {
	versions          map[string]string
	nextContentChange *time.Time
}

var appConfigCache struct {
	sync.Mutex
	environment string
	expiresAt   time.Time
	snapshot    appConfigSnapshot
	lastError   error
}

// A shared five-second snapshot bounds database reads independently of the
// number of devices. Concurrent misses share one refresh, not one query each.
func loadAppConfigSnapshot(ctx context.Context) (appConfigSnapshot, error) {
	environment := currentEnvironment()
	appConfigCache.Lock()
	defer appConfigCache.Unlock()
	now := time.Now().UTC()
	if appConfigCache.environment == environment && now.Before(appConfigCache.expiresAt) {
		return appConfigCache.snapshot, appConfigCache.lastError
	}
	fail := func(err error) (appConfigSnapshot, error) {
		appConfigCache.environment = environment
		appConfigCache.expiresAt = time.Now().UTC().Add(5 * time.Second)
		appConfigCache.lastError = err
		return appConfigSnapshot{}, err
	}
	rows, err := db.Get().QueryContext(ctx, `SELECT resource,revision,CASE WHEN resource='content' THEN
 (SELECT MIN(boundary) FROM (
 SELECT MIN(starts_at) AS boundary FROM whats_new_campaigns WHERE environment=$1 AND enabled=true AND starts_at>CURRENT_TIMESTAMP
 UNION ALL SELECT MIN(ends_at) FROM whats_new_campaigns WHERE environment=$1 AND enabled=true AND ends_at>CURRENT_TIMESTAMP
 ) upcoming) ELSE NULL END FROM app_config_versions ORDER BY resource`, environment)
	if err != nil {
		return fail(err)
	}
	defer rows.Close()
	snapshot := appConfigSnapshot{versions: map[string]string{}}
	for rows.Next() {
		var resource, revision string
		var boundary sql.NullTime
		if err := rows.Scan(&resource, &revision, &boundary); err != nil {
			return fail(err)
		}
		snapshot.versions[resource] = revision
		if boundary.Valid {
			value := boundary.Time.UTC()
			snapshot.nextContentChange = &value
		}
	}
	if err := rows.Err(); err != nil {
		return fail(err)
	}
	expires := time.Now().UTC().Add(5 * time.Second)
	if snapshot.nextContentChange != nil && snapshot.nextContentChange.Before(expires) {
		expires = *snapshot.nextContentChange
	}
	appConfigCache.environment = environment
	appConfigCache.snapshot = snapshot
	appConfigCache.lastError = nil
	appConfigCache.expiresAt = expires
	return snapshot, nil
}

// Public opaque revisions contain no account information or config contents.
func AppConfigVersions(c *gin.Context) {
	snapshot, err := loadAppConfigSnapshot(c.Request.Context())
	if err != nil {
		c.JSON(503, gin.H{"error": "configuration versions unavailable"})
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(200, gin.H{"versions": snapshot.versions, "content_next_change_at": snapshot.nextContentChange, "server_time": time.Now().UTC()})
}
