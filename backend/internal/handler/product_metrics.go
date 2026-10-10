package handler

import (
	"database/sql"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"vita/internal/db"
)

// Activity uses server-recorded dates. Authenticated app events are supplemented
// with durable actions so an offline or older client does not erase a real visit,
// message, gift or purchase. Each user is counted once per database calendar day.
const productActivityCTE = `WITH audience AS (
	SELECT id,created_at FROM users WHERE role_id='user' AND environment=$1
), activity_days AS (
	SELECT a.user_id,a.created_at::date AS day FROM analytics_events a
	JOIN audience u ON u.id=a.user_id
	WHERE a.environment=$1 AND a.created_at>=CURRENT_DATE-37 AND a.created_at<CURRENT_DATE
	UNION
	SELECT v.user_id,m.created_at::date FROM messages m
	JOIN conversations v ON v.id=m.conversation_id JOIN audience u ON u.id=v.user_id
	WHERE m.sender_type='user' AND m.created_at>=CURRENT_DATE-37 AND m.created_at<CURRENT_DATE
	UNION
	SELECT w.user_id,w.created_at::date FROM world_interactions w
	JOIN audience u ON u.id=w.user_id
	WHERE w.kind='visit' AND w.created_at>=CURRENT_DATE-37 AND w.created_at<CURRENT_DATE
	UNION
	SELECT p.user_id,p.purchased_at::date FROM billing_purchases p
	JOIN audience u ON u.id=p.user_id
	WHERE p.environment=$1 AND p.status='paid' AND p.purchased_at>=CURRENT_DATE-37 AND p.purchased_at<CURRENT_DATE
	UNION
	SELECT g.user_id,g.created_at::date FROM companion_gifts g
	JOIN audience u ON u.id=g.user_id
	WHERE g.created_at>=CURRENT_DATE-37 AND g.created_at<CURRENT_DATE
)`

const productSummarySQL = productActivityCTE + `,
window_activity AS (
	SELECT user_id,COUNT(*) AS active_days FROM activity_days
	WHERE day>=CURRENT_DATE-$2::int GROUP BY user_id
), window_new AS (
	SELECT id FROM audience WHERE created_at>=CURRENT_DATE-$2::int AND created_at<CURRENT_DATE
), window_messages AS (
	SELECT v.user_id,COUNT(*) AS messages FROM messages m
	JOIN conversations v ON v.id=m.conversation_id JOIN audience u ON u.id=v.user_id
	WHERE m.sender_type='user' AND m.created_at>=CURRENT_DATE-$2::int AND m.created_at<CURRENT_DATE
	GROUP BY v.user_id
), window_visits AS (
	SELECT w.user_id,COUNT(*) AS visits FROM world_interactions w
	JOIN audience u ON u.id=w.user_id
	WHERE w.kind='visit' AND w.created_at>=CURRENT_DATE-$2::int AND w.created_at<CURRENT_DATE
	GROUP BY w.user_id
), window_gifts AS (
	SELECT g.user_id,COUNT(*) AS gifts FROM companion_gifts g
	JOIN audience u ON u.id=g.user_id
	WHERE g.created_at>=CURRENT_DATE-$2::int AND g.created_at<CURRENT_DATE
	GROUP BY g.user_id
), meaningful_days AS (
	SELECT user_id,COUNT(DISTINCT day) AS days FROM (
		SELECT v.user_id,m.created_at::date AS day FROM messages m
		JOIN conversations v ON v.id=m.conversation_id JOIN audience u ON u.id=v.user_id
		WHERE m.sender_type='user' AND m.created_at>=CURRENT_DATE-$2::int AND m.created_at<CURRENT_DATE
		UNION ALL
		SELECT w.user_id,w.created_at::date FROM world_interactions w
		JOIN audience u ON u.id=w.user_id
		WHERE w.kind='visit' AND w.created_at>=CURRENT_DATE-$2::int AND w.created_at<CURRENT_DATE
		UNION ALL
		SELECT g.user_id,g.created_at::date FROM companion_gifts g
		JOIN audience u ON u.id=g.user_id
		WHERE g.created_at>=CURRENT_DATE-$2::int AND g.created_at<CURRENT_DATE
	) actions GROUP BY user_id
), window_purchases AS (
	SELECT p.user_id,p.kind,p.amount_minor,p.currency FROM billing_purchases p
	JOIN audience u ON u.id=p.user_id
	WHERE p.environment=$1 AND p.status='paid'
		AND p.purchased_at>=CURRENT_DATE-$2::int AND p.purchased_at<CURRENT_DATE
), due_experiences AS (
	SELECT e.id,s.closing_text FROM life_events e
	JOIN companions c ON c.id=e.companion_id JOIN audience u ON u.id=c.user_id
	LEFT JOIN companion_moment_sessions s ON s.event_id=e.id AND s.user_id=u.id
	WHERE e.event_type='shared_activity' AND e.generation_source='user_purchase'
		AND e.status<>'cancelled' AND e.start_time>=CURRENT_DATE-$2::int
		AND e.start_time<CURRENT_DATE AND e.end_time<CURRENT_DATE
)
SELECT
	(SELECT COUNT(*) FROM window_new),
	(SELECT COUNT(*) FROM window_activity),
	(SELECT COUNT(*) FROM window_activity WHERE active_days>=2),
	(SELECT COUNT(*) FROM activity_days WHERE day=CURRENT_DATE-1),
	(SELECT COUNT(DISTINCT user_id) FROM activity_days WHERE day>=CURRENT_DATE-30),
	(SELECT COUNT(*) FROM meaningful_days WHERE days>=2),
	(SELECT COUNT(*) FROM window_new n JOIN window_messages m ON m.user_id=n.id),
	(SELECT COUNT(*) FROM window_new n JOIN window_visits v ON v.user_id=n.id),
	(SELECT COUNT(*) FROM window_new n WHERE EXISTS(SELECT 1 FROM window_messages m WHERE m.user_id=n.id)
		OR EXISTS(SELECT 1 FROM window_visits v WHERE v.user_id=n.id)),
	(SELECT COALESCE(SUM(messages),0) FROM window_messages),
	(SELECT COALESCE(SUM(visits),0) FROM window_visits),
	(SELECT COALESCE(SUM(gifts),0) FROM window_gifts),
	(SELECT COUNT(DISTINCT user_id) FROM window_purchases),
	(SELECT COUNT(*) FROM window_purchases),
	(SELECT COUNT(*) FROM window_purchases WHERE kind='subscription'),
	(SELECT COUNT(*) FROM window_purchases WHERE kind='coin_pack'),
	(SELECT COUNT(*) FROM window_purchases WHERE amount_minor IS NOT NULL AND currency<>''),
	(SELECT COUNT(*) FROM due_experiences),
	(SELECT COUNT(*) FROM due_experiences WHERE COALESCE(closing_text,'')<>'')`

const productRetentionSQL = productActivityCTE + `,
cohorts AS (
	SELECT id,created_at::date AS registered_day FROM audience
	WHERE created_at>=CURRENT_DATE-37 AND created_at<CURRENT_DATE-1
)
SELECT
	COUNT(*) FILTER (WHERE c.registered_day>=CURRENT_DATE-31 AND c.registered_day<CURRENT_DATE-1),
	COUNT(*) FILTER (WHERE c.registered_day>=CURRENT_DATE-31 AND c.registered_day<CURRENT_DATE-1 AND d1.user_id IS NOT NULL),
	COUNT(*) FILTER (WHERE c.registered_day>=CURRENT_DATE-37 AND c.registered_day<CURRENT_DATE-7),
	COUNT(*) FILTER (WHERE c.registered_day>=CURRENT_DATE-37 AND c.registered_day<CURRENT_DATE-7 AND d7.user_id IS NOT NULL)
FROM cohorts c
LEFT JOIN activity_days d1 ON d1.user_id=c.id AND d1.day=c.registered_day+1
LEFT JOIN activity_days d7 ON d7.user_id=c.id AND d7.day=c.registered_day+7`

const productDailySQL = productActivityCTE + `,
days AS (SELECT generate_series((CURRENT_DATE-$2::int)::timestamp,(CURRENT_DATE-1)::timestamp,INTERVAL '1 day')::date AS day),
active_daily AS (SELECT day,COUNT(*) AS n FROM activity_days WHERE day>=CURRENT_DATE-$2::int GROUP BY day),
new_daily AS (SELECT created_at::date AS day,COUNT(*) AS n FROM audience WHERE created_at>=CURRENT_DATE-$2::int AND created_at<CURRENT_DATE GROUP BY 1),
paid_daily AS (SELECT p.purchased_at::date AS day,COUNT(DISTINCT p.user_id) AS n FROM billing_purchases p
	JOIN audience u ON u.id=p.user_id WHERE p.environment=$1 AND p.status='paid'
	AND p.purchased_at>=CURRENT_DATE-$2::int AND p.purchased_at<CURRENT_DATE GROUP BY 1),
message_daily AS (SELECT m.created_at::date AS day,COUNT(*) AS n FROM messages m
	JOIN conversations v ON v.id=m.conversation_id JOIN audience u ON u.id=v.user_id
	WHERE m.sender_type='user' AND m.created_at>=CURRENT_DATE-$2::int AND m.created_at<CURRENT_DATE GROUP BY 1),
visit_daily AS (SELECT w.created_at::date AS day,COUNT(*) AS n FROM world_interactions w
	JOIN audience u ON u.id=w.user_id WHERE w.kind='visit' AND w.created_at>=CURRENT_DATE-$2::int AND w.created_at<CURRENT_DATE GROUP BY 1),
gift_daily AS (SELECT g.created_at::date AS day,COUNT(*) AS n FROM companion_gifts g
	JOIN audience u ON u.id=g.user_id WHERE g.created_at>=CURRENT_DATE-$2::int AND g.created_at<CURRENT_DATE GROUP BY 1)
SELECT to_char(d.day,'YYYY-MM-DD'),COALESCE(a.n,0),COALESCE(n.n,0),COALESCE(p.n,0),
	COALESCE(m.n,0),COALESCE(v.n,0),COALESCE(g.n,0)
FROM days d LEFT JOIN active_daily a ON a.day=d.day LEFT JOIN new_daily n ON n.day=d.day
	LEFT JOIN paid_daily p ON p.day=d.day LEFT JOIN message_daily m ON m.day=d.day
	LEFT JOIN visit_daily v ON v.day=d.day LEFT JOIN gift_daily g ON g.day=d.day ORDER BY d.day`

type productRetention struct {
	CohortUsers   int     `json:"cohort_users"`
	RetainedUsers int     `json:"retained_users"`
	Rate          float64 `json:"rate"`
}

type productDaily struct {
	Date        string `json:"date"`
	ActiveUsers int    `json:"active_users"`
	NewUsers    int    `json:"new_users"`
	PayingUsers int    `json:"paying_users"`
	Messages    int    `json:"messages"`
	Visits      int    `json:"visits"`
	Gifts       int    `json:"gifts"`
}

type productMetricsResponse struct {
	Days                  int              `json:"days"`
	WindowStart           string           `json:"window_start"`
	WindowEndExclusive    string           `json:"window_end_exclusive"`
	GeneratedAt           time.Time        `json:"generated_at"`
	NewUsers              int              `json:"new_users"`
	ActiveUsers           int              `json:"active_users"`
	RepeatActiveUsers     int              `json:"repeat_active_users"`
	ActiveYesterday       int              `json:"active_yesterday"`
	Active30d             int              `json:"active_30d"`
	MeaningfulRepeatUsers int              `json:"meaningful_repeat_users"`
	NewChatUsers          int              `json:"new_chat_users"`
	NewVisitUsers         int              `json:"new_visit_users"`
	ActivatedNewUsers     int              `json:"activated_new_users"`
	Messages              int              `json:"messages"`
	Visits                int              `json:"visits"`
	Gifts                 int              `json:"gifts"`
	PayingUsers           int              `json:"paying_users"`
	Purchases             int              `json:"purchases"`
	SubscriptionPurchases int              `json:"subscription_purchases"`
	CoinPackPurchases     int              `json:"coin_pack_purchases"`
	PurchasesWithAmount   int              `json:"purchases_with_amount"`
	DueExperiences        int              `json:"due_experiences"`
	CompletedExperiences  int              `json:"completed_experiences"`
	D1                    productRetention `json:"d1"`
	D7                    productRetention `json:"d7"`
	Daily                 []productDaily   `json:"daily"`
}

// AdminProductMetrics reports complete database-calendar days only. D1/D7 use
// the latest 30 registration dates whose return day has fully elapsed.
func AdminProductMetrics(c *gin.Context) {
	days := 7
	if raw := c.Query("days"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || (parsed != 7 && parsed != 30) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "days must be 7 or 30"})
			return
		}
		days = parsed
	}
	tx, err := db.Get().BeginTx(c.Request.Context(), &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to begin product metrics snapshot"})
		return
	}
	defer tx.Rollback()
	var result productMetricsResponse
	result.Days = days
	result.Daily = make([]productDaily, 0, days)
	if err := tx.QueryRowContext(c.Request.Context(), productSummarySQL, currentEnvironment(), days).Scan(
		&result.NewUsers, &result.ActiveUsers, &result.RepeatActiveUsers,
		&result.ActiveYesterday, &result.Active30d, &result.MeaningfulRepeatUsers,
		&result.NewChatUsers, &result.NewVisitUsers, &result.ActivatedNewUsers,
		&result.Messages, &result.Visits, &result.Gifts, &result.PayingUsers,
		&result.Purchases, &result.SubscriptionPurchases, &result.CoinPackPurchases,
		&result.PurchasesWithAmount, &result.DueExperiences, &result.CompletedExperiences,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to collect product metrics"})
		return
	}
	if err := tx.QueryRowContext(c.Request.Context(), productRetentionSQL, currentEnvironment()).Scan(
		&result.D1.CohortUsers, &result.D1.RetainedUsers,
		&result.D7.CohortUsers, &result.D7.RetainedUsers,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to collect retention"})
		return
	}
	result.D1.Rate = productRate(result.D1.RetainedUsers, result.D1.CohortUsers)
	result.D7.Rate = productRate(result.D7.RetainedUsers, result.D7.CohortUsers)
	rows, err := tx.QueryContext(c.Request.Context(), productDailySQL, currentEnvironment(), days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to collect daily product metrics"})
		return
	}
	for rows.Next() {
		var day productDaily
		if err := rows.Scan(&day.Date, &day.ActiveUsers, &day.NewUsers, &day.PayingUsers,
			&day.Messages, &day.Visits, &day.Gifts); err != nil {
			rows.Close()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read daily product metrics"})
			return
		}
		result.Daily = append(result.Daily, day)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read daily product metrics"})
		return
	}
	rows.Close()
	var start, end time.Time
	if err := tx.QueryRowContext(c.Request.Context(), `SELECT (CURRENT_DATE-$1::int)::timestamp,CURRENT_DATE::timestamp`, days).Scan(&start, &end); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read metrics window"})
		return
	}
	result.WindowStart = start.Format("2006-01-02")
	result.WindowEndExclusive = end.Format("2006-01-02")
	result.GeneratedAt = time.Now().UTC()
	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to finish product metrics snapshot"})
		return
	}
	c.JSON(http.StatusOK, result)
}

func productRate(numerator, denominator int) float64 {
	if denominator == 0 {
		return 0
	}
	return float64(numerator) * 100 / float64(denominator)
}
