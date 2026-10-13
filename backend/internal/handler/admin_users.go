package handler

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lib/pq"

	"vita/internal/auth"
	"vita/internal/db"
)

// --- Admin user management ---
//
// All handlers in this file are mounted under /v1/admin/users and therefore
// already behind middleware.RequireAdmin(). They manage *regular* user
// accounts only: administrator accounts are never listed for mutation targets
// that would let an operator lock the console out of itself.

// AdminUser is the admin-facing view of a user account.
type AdminUser struct {
	ID                  string                    `json:"id"`
	Email               string                    `json:"email"`
	Role                string                    `json:"role"`
	Timezone            string                    `json:"timezone"`
	Banned              bool                      `json:"banned"`
	CreatedAt           time.Time                 `json:"created_at"`
	UpdatedAt           time.Time                 `json:"updated_at"`
	IsSubscribed        bool                      `json:"is_subscribed"`
	SubscriptionRefunds []AdminSubscriptionRefund `json:"subscription_refunds,omitempty"`
}

type AdminSubscriptionRefund struct {
	Store        string     `json:"store"`
	PurchasedAt  *time.Time `json:"purchased_at"`
	RefundStatus string     `json:"refund_status"`
}

const adminSubscriptionRefundColumns = `COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'store',sub.store,
 'purchased_at',CASE WHEN sub.period_type='TRIAL' THEN NULL ELSE to_char(sub.current_period_start,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') END,
 'refund_status',CASE
 WHEN sub.current_period_start IS NULL OR sub.current_period_start>CURRENT_TIMESTAMP OR sub.period_type='TRIAL' THEN 'unknown'
 WHEN sub.store IN ('APP_STORE','MAC_APP_STORE') THEN 'apple_review'
 WHEN sub.store='PLAY_STORE' AND sub.period_type IN ('NORMAL','INTRO') AND sub.current_period_start IS NOT NULL AND sub.current_period_start<=CURRENT_TIMESTAMP THEN
 CASE WHEN sub.current_period_start+INTERVAL '48 hours'>CURRENT_TIMESTAMP THEN 'google_within_48h' ELSE 'google_after_48h' END
 ELSE 'unknown' END) ORDER BY sub.current_period_start DESC NULLS LAST,sub.id)
 FROM subscriptions sub WHERE sub.user_id=users.id AND sub.status='active' AND (sub.current_period_end IS NULL OR sub.current_period_end>CURRENT_TIMESTAMP)), '[]'::jsonb)::text`

// AdminUserDetail adds per-account usage counts to the base fields.
type AdminUserDetail struct {
	AdminUser
	Companions    int `json:"companions"`
	Conversations int `json:"conversations"`
	Messages      int `json:"messages"`
	Memories      int `json:"memories"`
}

// AdminUserListResponse is the paginated list shape consumed by the dashboard.
type AdminUserListResponse struct {
	Items      []AdminUser `json:"items"`
	Total      int         `json:"total"`
	Page       int         `json:"page"`
	PageSize   int         `json:"page_size"`
	TotalPages int         `json:"total_pages"`
}

const adminUserSubscriptionExists = `EXISTS(SELECT 1 FROM subscriptions sub WHERE sub.user_id=users.id AND sub.status='active' AND (sub.current_period_end IS NULL OR sub.current_period_end>CURRENT_TIMESTAMP))`

const adminUserColumns = `id, email, COALESCE(role_id, 'user'), COALESCE(timezone, 'UTC'), COALESCE(banned, false), created_at, updated_at, ` + adminUserSubscriptionExists

// rowScanner is satisfied by both *sql.Row and *sql.Rows.
type rowScanner interface {
	Scan(dest ...any) error
}

func scanAdminUser(sc rowScanner) (AdminUser, error) {
	var u AdminUser
	err := sc.Scan(&u.ID, &u.Email, &u.Role, &u.Timezone, &u.Banned, &u.CreatedAt, &u.UpdatedAt, &u.IsSubscribed)
	return u, err
}

func adminUserByID(id string) (AdminUser, error) {
	row := db.Get().QueryRow(`SELECT `+adminUserColumns+` FROM users WHERE id = $1`, id)
	u, err := scanAdminUser(row)
	if errors.Is(err, sql.ErrNoRows) {
		return AdminUser{}, errUserNotFound
	}
	return u, err
}

var errUserNotFound = errors.New("user not found")

// --- List ---

// AdminListUsers returns a page of users. Query parameters:
//
//	page         int    (default 1)
//	page_size    int    (default 10, max 100)
//	q            string (case-insensitive email substring)
//	role         string ("user" | "admin")
//	status       string ("active" | "banned")
//	subscription string ("subscribed" | "unsubscribed")
func AdminListUsers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "10"))
	if pageSize < 1 {
		pageSize = 10
	}
	if pageSize > 100 {
		pageSize = 100
	}

	var conds []string
	var args []any

	if q := strings.TrimSpace(c.Query("q")); q != "" {
		args = append(args, "%"+q+"%")
		conds = append(conds, fmt.Sprintf("email ILIKE $%d", len(args)))
	}
	if role := strings.TrimSpace(c.Query("role")); role != "" {
		args = append(args, role)
		conds = append(conds, fmt.Sprintf("role_id = $%d", len(args)))
	}
	if status := strings.TrimSpace(c.Query("status")); status == "banned" || status == "active" {
		args = append(args, status == "banned")
		conds = append(conds, fmt.Sprintf("banned = $%d", len(args)))
	}
	if subscription := strings.TrimSpace(c.Query("subscription")); subscription != "" {
		if subscription != "subscribed" && subscription != "unsubscribed" {
			c.JSON(400, gin.H{"error": "invalid subscription filter"})
			return
		}
		condition := adminUserSubscriptionExists
		if subscription == "unsubscribed" {
			condition = "NOT " + condition
		}
		conds = append(conds, condition)
	}
	args = append(args, currentEnvironment())
	conds = append(conds, fmt.Sprintf("environment = $%d", len(args)))

	where := ""
	if len(conds) > 0 {
		where = " WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := db.Get().QueryRow(`SELECT COUNT(*) FROM users`+where, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to count users"})
		return
	}

	args = append(args, pageSize, (page-1)*pageSize)
	rows, err := db.Get().Query(
		`SELECT `+adminUserColumns+`, `+adminSubscriptionRefundColumns+` FROM users`+where+` ORDER BY created_at DESC, email ASC
		 LIMIT $`+strconv.Itoa(len(args)-1)+` OFFSET $`+strconv.Itoa(len(args)),
		args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list users"})
		return
	}
	defer rows.Close()

	items := make([]AdminUser, 0, pageSize)
	for rows.Next() {
		var u AdminUser
		var rawRefunds string
		err := rows.Scan(&u.ID, &u.Email, &u.Role, &u.Timezone, &u.Banned, &u.CreatedAt, &u.UpdatedAt, &u.IsSubscribed, &rawRefunds)
		if err == nil {
			err = json.Unmarshal([]byte(rawRefunds), &u.SubscriptionRefunds)
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read users"})
			return
		}
		items = append(items, u)
	}

	if err := rows.Err(); err != nil {
		c.JSON(500, gin.H{"error": "failed to read users"})
		return
	}
	totalPages := (total + pageSize - 1) / pageSize
	c.JSON(http.StatusOK, AdminUserListResponse{
		Items:      items,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	})
}

// --- Detail ---

func AdminGetUser(c *gin.Context) {
	u, err := adminUserByID(c.Param("id"))
	if err != nil {
		if errors.Is(err, errUserNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}

	var d AdminUserDetail
	d.AdminUser = u
	err = db.Get().QueryRow(`
		SELECT
			(SELECT COUNT(*) FROM companions WHERE user_id = $1),
			(SELECT COUNT(*) FROM conversations WHERE user_id = $1),
			(SELECT COUNT(*) FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = $1)),
			(SELECT COUNT(*) FROM memories WHERE companion_id IN (SELECT id FROM companions WHERE user_id = $1))`,
		u.ID).Scan(&d.Companions, &d.Conversations, &d.Messages, &d.Memories)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to collect user stats"})
		return
	}

	c.JSON(http.StatusOK, d)
}

// --- Create ---

type AdminCreateUserRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password"`
	Role     string `json:"role"`
	Timezone string `json:"timezone"`
}

func AdminCreateUser(c *gin.Context) {
	var req AdminCreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	role := strings.TrimSpace(req.Role)
	if role == "" {
		role = "user"
	}
	if role != "user" && role != "admin" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "role must be 'user' or 'admin'"})
		return
	}
	timezone := strings.TrimSpace(req.Timezone)
	if timezone == "" {
		timezone = "UTC"
	}
	// User accounts are always stored in the single production scope.
	environment := currentEnvironment()

	var exists bool
	if err := db.Get().QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)`, req.Email).Scan(&exists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check email"})
		return
	}
	if exists {
		c.JSON(http.StatusConflict, gin.H{"error": "email already exists"})
		return
	}

	passwordHash := ""
	if req.Password != "" {
		hash, err := auth.HashPassword(req.Password)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
			return
		}
		passwordHash = hash
	}

	id := uuid.New().String()
	if _, err := db.Get().Exec(
		`INSERT INTO users (id, email, role_id, password_hash, timezone, environment) VALUES ($1, $2, $3, $4, $5, $6)`,
		id, req.Email, role, passwordHash, timezone, environment); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	c.JSON(http.StatusCreated, AdminUser{
		ID: id, Email: req.Email, Role: role, Timezone: timezone, Banned: false,
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	})
}

// --- Update ---

// AdminUpdateUserRequest uses pointers so omitted fields stay unchanged. An
// empty password string means "keep the current password"; any non-empty value
// replaces it.
type AdminUpdateUserRequest struct {
	Email    *string `json:"email"`
	Password *string `json:"password"`
	Role     *string `json:"role"`
	Timezone *string `json:"timezone"`
}

func AdminUpdateUser(c *gin.Context) {
	id := c.Param("id")
	var req AdminUpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Load current row including the hash (needed to decide whether to rehash).
	var cur AdminUser
	var curHash string
	err := db.Get().QueryRow(
		`SELECT `+adminUserColumns+`, COALESCE(password_hash, '') FROM users WHERE id = $1`, id).
		Scan(&cur.ID, &cur.Email, &cur.Role, &cur.Timezone, &cur.Banned, &cur.CreatedAt, &cur.UpdatedAt, &cur.IsSubscribed, &curHash)
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}

	newEmail := cur.Email
	if req.Email != nil && strings.TrimSpace(*req.Email) != "" {
		newEmail = strings.TrimSpace(*req.Email)
		var dup bool
		if err := db.Get().QueryRow(
			`SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND id <> $2)`, newEmail, id).Scan(&dup); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check email"})
			return
		}
		if dup {
			c.JSON(http.StatusConflict, gin.H{"error": "email already exists"})
			return
		}
	}

	newRole := cur.Role
	if req.Role != nil && strings.TrimSpace(*req.Role) != "" {
		newRole = strings.TrimSpace(*req.Role)
		if newRole != "user" && newRole != "admin" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "role must be 'user' or 'admin'"})
			return
		}
		// An administrator must not be able to strip their own role — that
		// would leave the console with a valid token but no admin access.
		if id == c.GetString("user_id") && newRole != "admin" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "cannot change your own role"})
			return
		}
	}

	newTimezone := cur.Timezone
	if req.Timezone != nil && strings.TrimSpace(*req.Timezone) != "" {
		newTimezone = strings.TrimSpace(*req.Timezone)
	}

	newEnvironment := currentEnvironment()

	newHash := curHash
	if req.Password != nil && *req.Password != "" {
		hash, err := auth.HashPassword(*req.Password)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
			return
		}
		newHash = hash
	}

	if _, err := db.Get().Exec(
		`UPDATE users SET email = $1, role_id = $2, timezone = $3, password_hash = $4, environment = $5, updated_at = CURRENT_TIMESTAMP WHERE id = $6`,
		newEmail, newRole, newTimezone, newHash, newEnvironment, id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update user"})
		return
	}

	u, err := adminUserByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reload user"})
		return
	}
	c.JSON(http.StatusOK, u)
}

// --- Delete ---

// AdminDeleteUser removes a regular user together with all of their data.
// Administrator accounts and the operator's own account are protected.
func AdminDeleteUser(c *gin.Context) {
	id := c.Param("id")

	u, err := adminUserByID(id)
	if err != nil {
		if errors.Is(err, errUserNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		logAdminUserDeletionFailure(c, id, "load_user", "", err)
		return
	}
	if u.Role == "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot delete an administrator account"})
		return
	}
	if id == c.GetString("user_id") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot delete your own account"})
		return
	}

	tx, err := db.Get().BeginTx(c.Request.Context(), nil)
	if err != nil {
		logAdminUserDeletionFailure(c, id, "begin", "", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to start transaction"})
		return
	}
	defer tx.Rollback() //nolint:errcheck // no-op after commit

	// Delete children in FK order: messages → conversations, memories/life/
	// states → companions, companions → user, then the account itself.
	steps := []struct {
		name  string
		query string
		args  []any
	}{
		{"invitation_rewards", `DELETE FROM invitation_rewards WHERE inviter_user_id = $1 OR invited_user_id = $1`, []any{id}},
		{"billing_purchases", `DELETE FROM billing_purchases WHERE user_id = $1`, []any{id}},
		{"subscriptions", `DELETE FROM subscriptions WHERE user_id = $1`, []any{id}},
		{"credit_transactions", `DELETE FROM credit_transactions WHERE user_id = $1`, []any{id}},
		{"messages", `DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = $1)`, []any{id}},
		{"conversations", `DELETE FROM conversations WHERE user_id = $1`, []any{id}},
		{"memories", `DELETE FROM memories WHERE companion_id IN (SELECT id FROM companions WHERE user_id = $1)`, []any{id}},
		{"life_events", `DELETE FROM life_events WHERE companion_id IN (SELECT id FROM companions WHERE user_id = $1)`, []any{id}},
		{"relationship_states", `DELETE FROM relationship_states WHERE companion_id IN (SELECT id FROM companions WHERE user_id = $1)`, []any{id}},
		{"companion_states", `DELETE FROM companion_states WHERE companion_id IN (SELECT id FROM companions WHERE user_id = $1)`, []any{id}},
		{"companions", `DELETE FROM companions WHERE user_id = $1`, []any{id}},
		{"verification_codes", `DELETE FROM verification_codes WHERE email = $1`, []any{u.Email}},
		{"media_assets", `DELETE FROM media_assets WHERE user_id=$1`, []any{id}},
		{"users", `DELETE FROM users WHERE id = $1`, []any{id}},
	}
	for _, step := range steps {
		if _, err := tx.ExecContext(c.Request.Context(), step.query, step.args...); err != nil {
			logAdminUserDeletionFailure(c, id, "delete_"+step.name, step.query, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete user data"})
			return
		}
	}

	if err := tx.Commit(); err != nil {
		logAdminUserDeletionFailure(c, id, "commit", "", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to commit deletion"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "user deleted"})
}

// Log statement templates and database metadata, never bound values or the
// PostgreSQL Detail field (which can contain private row contents).
func logAdminUserDeletionFailure(c *gin.Context, userID, stage, statement string, err error) {
	var pgErr *pq.Error
	if errors.As(err, &pgErr) {
		log.Printf("[ADMIN_USER_DELETE] request_id=%q actor_id=%q target_id=%q stage=%q sql=%q sqlstate=%q schema=%q table=%q column=%q constraint=%q message=%q",
			c.GetString("request_id"), c.GetString("user_id"), userID, stage, statement,
			string(pgErr.Code), pgErr.Schema, pgErr.Table, pgErr.Column, pgErr.Constraint, pgErr.Message)
		return
	}
	log.Printf("[ADMIN_USER_DELETE] request_id=%q actor_id=%q target_id=%q stage=%q sql=%q error=%q",
		c.GetString("request_id"), c.GetString("user_id"), userID, stage, statement, err.Error())
}

// --- Ban / Unban ---

// AdminSetBanned flips the banned flag for a regular user. Banned accounts can
// no longer sign in through any login flow (enforced in the login handlers).
func AdminSetBanned(c *gin.Context, banned bool) {
	id := c.Param("id")

	u, err := adminUserByID(id)
	if err != nil {
		if errors.Is(err, errUserNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load user"})
		return
	}
	if u.Role == "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "cannot ban an administrator account"})
		return
	}
	if banned && id == c.GetString("user_id") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot ban your own account"})
		return
	}

	if _, err := db.Get().Exec(`UPDATE users SET banned = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`, banned, id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update user"})
		return
	}

	updated, err := adminUserByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reload user"})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// userBanned reports whether an account is banned; a missing account counts as
// not banned so callers can rely on their own not-found handling.
func userBanned(userID string) (bool, error) {
	var banned bool
	err := db.Get().QueryRow(`SELECT COALESCE(banned, false) FROM users WHERE id = $1`, userID).Scan(&banned)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return banned, err
}
