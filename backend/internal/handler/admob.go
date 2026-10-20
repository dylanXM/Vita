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

	"vita/internal/db"
)

type admobSettings struct {
	RewardedEnabled           bool   `json:"rewarded_enabled"`
	BannerEnabled             bool   `json:"banner_enabled"`
	InterstitialEnabled       bool   `json:"interstitial_enabled"`
	ShowToSubscribers         bool   `json:"show_to_subscribers"`
	RewardCredits             int    `json:"reward_credits"`
	DailyRewardLimit          int    `json:"daily_reward_limit"`
	AndroidRewardedUnitID     string `json:"android_rewarded_unit_id"`
	IOSRewardedUnitID         string `json:"ios_rewarded_unit_id"`
	AndroidBannerUnitID       string `json:"android_banner_unit_id"`
	IOSBannerUnitID           string `json:"ios_banner_unit_id"`
	AndroidInterstitialUnitID string `json:"android_interstitial_unit_id"`
	IOSInterstitialUnitID     string `json:"ios_interstitial_unit_id"`
}

func loadAdmobSettings() (admobSettings, error) {
	var s admobSettings
	err := db.Get().QueryRow(`SELECT rewarded_enabled,banner_enabled,interstitial_enabled,
		show_to_subscribers,reward_credits,daily_reward_limit,
		android_rewarded_unit_id,ios_rewarded_unit_id,
		android_banner_unit_id,ios_banner_unit_id,
		android_interstitial_unit_id,ios_interstitial_unit_id
		FROM admob_settings WHERE environment=$1`, currentEnvironment()).Scan(
		&s.RewardedEnabled, &s.BannerEnabled, &s.InterstitialEnabled,
		&s.ShowToSubscribers, &s.RewardCredits, &s.DailyRewardLimit,
		&s.AndroidRewardedUnitID, &s.IOSRewardedUnitID,
		&s.AndroidBannerUnitID, &s.IOSBannerUnitID,
		&s.AndroidInterstitialUnitID, &s.IOSInterstitialUnitID)
	return s, err
}

func AdminGetAdmobSettings(c *gin.Context) {
	s, err := loadAdmobSettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load AdMob settings"})
		return
	}
	c.JSON(http.StatusOK, s)
}

func AdminUpdateAdmobSettings(c *gin.Context) {
	var s admobSettings
	if err := c.ShouldBindJSON(&s); err != nil || s.RewardCredits < 1 || s.RewardCredits > 1000 ||
		s.DailyRewardLimit < 0 || s.DailyRewardLimit > 100 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid AdMob settings"})
		return
	}
	if _, err := db.Get().Exec(`UPDATE admob_settings SET
		rewarded_enabled=$1,banner_enabled=$2,interstitial_enabled=$3,
		show_to_subscribers=$4,reward_credits=$5,daily_reward_limit=$6,
		android_rewarded_unit_id=$7,ios_rewarded_unit_id=$8,
		android_banner_unit_id=$9,ios_banner_unit_id=$10,
		android_interstitial_unit_id=$11,ios_interstitial_unit_id=$12,
		updated_at=CURRENT_TIMESTAMP WHERE environment=$13`,
		s.RewardedEnabled, s.BannerEnabled, s.InterstitialEnabled,
		s.ShowToSubscribers, s.RewardCredits, s.DailyRewardLimit,
		strings.TrimSpace(s.AndroidRewardedUnitID), strings.TrimSpace(s.IOSRewardedUnitID),
		strings.TrimSpace(s.AndroidBannerUnitID), strings.TrimSpace(s.IOSBannerUnitID),
		strings.TrimSpace(s.AndroidInterstitialUnitID), strings.TrimSpace(s.IOSInterstitialUnitID),
		currentEnvironment()); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save AdMob settings"})
		return
	}
	AdminGetAdmobSettings(c)
}

func admobUnit(s admobSettings, platform, format string) string {
	switch platform + "/" + format {
	case "android/rewarded":
		return s.AndroidRewardedUnitID
	case "ios/rewarded":
		return s.IOSRewardedUnitID
	case "android/banner":
		return s.AndroidBannerUnitID
	case "ios/banner":
		return s.IOSBannerUnitID
	case "android/interstitial":
		return s.AndroidInterstitialUnitID
	case "ios/interstitial":
		return s.IOSInterstitialUnitID
	}
	return ""
}

func admobPlatform(c *gin.Context) string {
	platform := c.GetHeader("X-Vita-Platform")
	if platform == "android" || platform == "ios" {
		return platform
	}
	return ""
}

func rewardCountToday(userID string) (int, error) {
	var count int
	err := db.Get().QueryRow(`SELECT COUNT(*) FROM admob_reward_events WHERE user_id=$1
		AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC')`, userID).Scan(&count)
	return count, err
}

func GetAdmobConfig(c *gin.Context) {
	s, err := loadAdmobSettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load ads"})
		return
	}
	platform := admobPlatform(c)
	userID := c.GetString("user_id")
	subscribed, err := userHasActiveSubscription(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load subscription"})
		return
	}
	count, err := rewardCountToday(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load ad rewards"})
		return
	}
	showDisplayAds := !subscribed || s.ShowToSubscribers
	c.JSON(http.StatusOK, gin.H{
		"show_to_subscribers":  s.ShowToSubscribers,
		"rewarded_unit_id":     admobUnit(s, platform, "rewarded"),
		"rewarded_enabled":     s.RewardedEnabled && s.DailyRewardLimit > count && platform != "",
		"reward_credits":       s.RewardCredits,
		"daily_reward_limit":   s.DailyRewardLimit,
		"remaining_today":      max(0, s.DailyRewardLimit-count),
		"banner_enabled":       s.BannerEnabled && showDisplayAds && platform != "",
		"banner_unit_id":       admobUnit(s, platform, "banner"),
		"interstitial_enabled": s.InterstitialEnabled && showDisplayAds && platform != "",
		"interstitial_unit_id": admobUnit(s, platform, "interstitial"),
	})
}

func CreateAdmobRewardSession(c *gin.Context) {
	s, err := loadAdmobSettings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load ads"})
		return
	}
	unit := admobUnit(s, admobPlatform(c), "rewarded")
	if !s.RewardedEnabled || s.DailyRewardLimit == 0 || unit == "" {
		c.JSON(http.StatusConflict, gin.H{"error": "rewarded ads unavailable"})
		return
	}
	userID := c.GetString("user_id")
	count, err := rewardCountToday(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load ad rewards"})
		return
	}
	if count >= s.DailyRewardLimit {
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "daily ad reward limit reached"})
		return
	}
	id := uuid.NewString()
	if _, err := db.Get().Exec(`INSERT INTO admob_reward_sessions(id,user_id,environment,ad_unit_id,credits)
		VALUES($1,$2,$3,$4,$5)`, id, userID, currentEnvironment(), unit, s.RewardCredits); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to prepare ad reward"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"session_id": id, "ad_unit_id": unit, "reward_credits": s.RewardCredits})
}

// AdmobRewardCallback is public because Google calls it without a Vita token.
// The signature is verified before any callback field is trusted.
func AdmobRewardCallback(c *gin.Context) {
	if err := verifyAdmobCallback(c.Request.Context(), c.Request.URL.RawQuery); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid AdMob signature"})
		return
	}
	q := c.Request.URL.Query()
	sessionID, userID, transactionID := q.Get("custom_data"), q.Get("user_id"), q.Get("transaction_id")
	if sessionID == "" || userID == "" || transactionID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing ad reward reference"})
		return
	}
	// AdMob timestamps are milliseconds since the Unix epoch.
	callbackTime, err := strconv.ParseInt(q.Get("timestamp"), 10, 64)
	if err != nil ||
		time.Since(time.UnixMilli(callbackTime)) > 2*time.Hour ||
		time.Until(time.UnixMilli(callbackTime)) > 5*time.Minute {
		c.JSON(http.StatusBadRequest, gin.H{"error": "expired ad reward"})
		return
	}
	if err := applyAdmobReward(sessionID, userID, transactionID, q.Get("ad_unit")); err != nil {
		if errors.Is(err, errAdmobRewardRejected) {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "ad reward temporarily unavailable"})
		return
	}
	c.Status(http.StatusOK)
}

var errAdmobRewardRejected = errors.New("ad reward rejected")

func applyAdmobReward(sessionID, userID, transactionID, callbackUnit string) error {
	tx, err := db.Get().Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var sessionUser, environment, unit string
	var credits int
	var createdAt time.Time
	var consumedAt sql.NullTime
	var previousTransaction sql.NullString
	if err := tx.QueryRow(`SELECT user_id,environment,ad_unit_id,credits,created_at,consumed_at
		,transaction_id FROM admob_reward_sessions WHERE id=$1 FOR UPDATE`, sessionID).Scan(
		&sessionUser, &environment, &unit, &credits, &createdAt, &consumedAt, &previousTransaction); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return errAdmobRewardRejected
		}
		return err
	}
	if consumedAt.Valid {
		if previousTransaction.String == transactionID {
			return nil
		}
		return errAdmobRewardRejected
	}
	if sessionUser != userID || environment != currentEnvironment() ||
		(callbackUnit != unit && callbackUnit != unit[strings.LastIndex(unit, "/")+1:]) ||
		time.Since(createdAt) > 2*time.Hour {
		return errAdmobRewardRejected
	}
	var balance int
	if err := tx.QueryRow(`SELECT credits_balance FROM users WHERE id=$1 FOR UPDATE`, userID).Scan(&balance); err != nil {
		return err
	}
	var limit, count int
	if err := tx.QueryRow(`SELECT daily_reward_limit FROM admob_settings WHERE environment=$1`, environment).Scan(&limit); err != nil {
		return err
	}
	if err := tx.QueryRow(`SELECT COUNT(*) FROM admob_reward_events WHERE user_id=$1
		AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC')`, userID).Scan(&count); err != nil {
		return err
	}
	if count >= limit {
		return errAdmobRewardRejected
	}
	balance += credits
	if _, err := tx.Exec(`UPDATE users SET credits_balance=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2`, balance, userID); err != nil {
		return err
	}
	if _, err := tx.Exec(`INSERT INTO admob_reward_events(transaction_id,session_id,user_id,environment,credits)
		VALUES($1,$2,$3,$4,$5)`, transactionID, sessionID, userID, environment, credits); err != nil {
		return err
	}
	if _, err := tx.Exec(`INSERT INTO credit_transactions(id,user_id,amount,balance_after,kind,description,platform,environment)
		VALUES($1,$2,$3,$4,'ad_reward','',$5,$6)`, uuid.NewString(), userID, credits, balance, "admob", environment); err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE admob_reward_sessions SET consumed_at=(now() AT TIME ZONE 'UTC'),transaction_id=$1 WHERE id=$2`, transactionID, sessionID); err != nil {
		return err
	}
	return tx.Commit()
}
