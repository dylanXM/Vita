package handler

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"vita/internal/db"
)

const companionRecoveryWindow = 30 * 24 * time.Hour

// ListDeletedCompanions returns user-owned companions that are still inside
// the recovery window. Expired records are removed before the list is read.
func ListDeletedCompanions(c *gin.Context) {
	if err := PurgeExpiredCompanions(c.Request.Context()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to clean expired companions"})
		return
	}
	rows, err := db.Get().QueryContext(c.Request.Context(), `
		SELECT c.id,c.name,COALESCE(c.city,''),COALESCE(c.occupation,''),
		       COALESCE(p.image_url,''),c.deleted_at,c.purge_after,
		       EXISTS(SELECT 1 FROM subscriptions s WHERE s.user_id=c.user_id AND s.status='active'
		         AND (s.current_period_end IS NULL OR s.current_period_end>CURRENT_TIMESTAMP))
		FROM companions c LEFT JOIN companion_portraits p ON p.id=c.portrait_id
		WHERE c.user_id=$1 AND c.deleted_at IS NOT NULL AND c.purge_after>CURRENT_TIMESTAMP
		ORDER BY c.deleted_at DESC`, c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list deleted companions"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name, city, occupation, portraitURL string
		var deletedAt, purgeAfter time.Time
		var lifeRunning bool
		if err := rows.Scan(&id, &name, &city, &occupation, &portraitURL, &deletedAt, &purgeAfter, &lifeRunning); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read deleted companions"})
			return
		}
		items = append(items, gin.H{
			"id": id, "name": name, "city": city, "occupation": occupation,
			"portrait_url": portraitURL, "deleted_at": deletedAt, "purge_after": purgeAfter,
			"life_engine_running": lifeRunning,
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read deleted companions"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func RestoreCompanion(c *gin.Context) {
	userID := c.GetString("user_id")
	companionID := c.Param("id")
	subscribed, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check subscription"})
		return
	}
	result, err := db.Get().ExecContext(c.Request.Context(), `UPDATE companions SET
		active=true,deleted_at=NULL,purge_after=NULL,life_enabled=$3,friendship_active=$3,
		subscription_paused_at=CASE WHEN $3 THEN NULL ELSE COALESCE(subscription_paused_at,CURRENT_TIMESTAMP) END,
		updated_at=CURRENT_TIMESTAMP
		WHERE id=$1 AND user_id=$2 AND is_default=false AND deleted_at IS NOT NULL
		AND purge_after>CURRENT_TIMESTAMP`, companionID, userID, subscribed)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to restore companion"})
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "companion is no longer recoverable"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "companion restored", "life_engine_running": subscribed})
}

// PurgeExpiredCompanions permanently removes companions after their recovery
// deadline. It is safe to call from multiple API/worker instances because each
// transaction locks one candidate before deleting it.
func PurgeExpiredCompanions(ctx context.Context) error {
	for {
		tx, err := db.Get().BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		var id string
		err = tx.QueryRowContext(ctx, `SELECT id FROM companions
			WHERE deleted_at IS NOT NULL AND purge_after<=CURRENT_TIMESTAMP
			ORDER BY purge_after LIMIT 1 FOR UPDATE SKIP LOCKED`).Scan(&id)
		if errors.Is(err, sql.ErrNoRows) {
			_ = tx.Rollback()
			return nil
		}
		if err != nil {
			_ = tx.Rollback()
			return err
		}
		if err = permanentlyDeleteCompanion(ctx, tx, id); err != nil {
			_ = tx.Rollback()
			return err
		}
		if err = tx.Commit(); err != nil {
			return err
		}
	}
}

func permanentlyDeleteCompanion(ctx context.Context, tx *sql.Tx, id string) error {
	statements := []string{
		`DELETE FROM notification_outbox WHERE companion_id=$1`,
		`DELETE FROM pending_agent_replies WHERE companion_id=$1`,
		`DELETE FROM moment_posts WHERE author_companion_id=$1`,
		`DELETE FROM companion_connection_days WHERE companion_id=$1`,
		`UPDATE life_events SET related_companion_id=NULL,social_event_id=NULL WHERE related_companion_id=$1`,
		`UPDATE life_events SET social_event_id=NULL WHERE social_event_id IN (SELECT id FROM companion_social_events WHERE actor_companion_id=$1 OR related_companion_id=$1)`,
		`DELETE FROM moment_posts WHERE social_event_id IN (SELECT id FROM companion_social_events WHERE actor_companion_id=$1 OR related_companion_id=$1)`,
		`DELETE FROM companion_social_events WHERE actor_companion_id=$1 OR related_companion_id=$1`,
		`DELETE FROM companion_relationships WHERE companion_a_id=$1 OR companion_b_id=$1`,
		`DELETE FROM media_assets WHERE id IN (
			SELECT split_part(m.media_url,'/',4) FROM messages m
			JOIN conversations cv ON cv.id=m.conversation_id
			WHERE cv.companion_id=$1 AND m.media_url LIKE '/v1/media/%'
		)`,
		`DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE companion_id=$1)`,
		`DELETE FROM conversations WHERE companion_id=$1`,
		`DELETE FROM companion_keepsakes WHERE companion_id=$1`,
		`DELETE FROM companion_outfits WHERE companion_id=$1`,
		`DELETE FROM companion_gifts WHERE companion_id=$1`,
		`DELETE FROM memories WHERE companion_id=$1`,
		`DELETE FROM life_events WHERE companion_id=$1`,
		`DELETE FROM companion_days WHERE companion_id=$1`,
		`DELETE FROM relationship_states WHERE companion_id=$1`,
		`DELETE FROM companion_states WHERE companion_id=$1`,
		`UPDATE credit_spends SET companion_id=NULL WHERE companion_id=$1`,
		`UPDATE agent_runs SET companion_id=NULL WHERE companion_id=$1`,
		`DELETE FROM companions WHERE id=$1`,
	}
	for _, statement := range statements {
		if _, err := tx.ExecContext(ctx, statement, id); err != nil {
			return err
		}
	}
	return nil
}
