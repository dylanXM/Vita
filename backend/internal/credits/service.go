package credits

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrProductNotFound    = errors.New("credit product not found")
	ErrInsufficientCredit = errors.New("insufficient credits")
	ErrSpendInProgress    = errors.New("credit spend is still processing")
	ErrSpendRefunded      = errors.New("credit spend was refunded")
)

type Product struct {
	Key            string         `json:"key"`
	Category       string         `json:"category"`
	NameKey        string         `json:"name_key"`
	DescriptionKey string         `json:"description_key"`
	Emoji          string         `json:"emoji"`
	Coins          int            `json:"coins"`
	Enabled        bool           `json:"enabled"`
	SortOrder      int            `json:"sort_order"`
	Metadata       map[string]any `json:"metadata"`
}

type Reservation struct {
	ID         string
	Product    Product
	Balance    int
	Status     string
	Result     map[string]any
	Idempotent bool
}

type ReserveParams struct {
	UserID         string
	CompanionID    string
	Environment    string
	Platform       string
	ProductKey     string
	IdempotencyKey string
	ReferenceType  string
	Metadata       map[string]any
}

func ListProducts(ctx context.Context, database *sql.DB, environment, category string) ([]Product, error) {
	query := `SELECT product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::text
		FROM credit_products WHERE environment=$1 AND enabled=true
		AND COALESCE((metadata->>'hidden_from_catalog')::boolean,false)=false`
	args := []any{environment}
	if strings.TrimSpace(category) != "" {
		query += ` AND category=$2`
		args = append(args, strings.TrimSpace(category))
	}
	query += ` ORDER BY category,sort_order,product_key`
	rows, err := database.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	products := []Product{}
	for rows.Next() {
		product, err := scanProduct(rows)
		if err != nil {
			return nil, err
		}
		products = append(products, product)
	}
	return products, rows.Err()
}

func Reserve(ctx context.Context, database *sql.DB, params ReserveParams) (*Reservation, error) {
	params.ProductKey = strings.TrimSpace(params.ProductKey)
	params.IdempotencyKey = strings.TrimSpace(params.IdempotencyKey)
	if params.ProductKey == "" || params.IdempotencyKey == "" || len(params.IdempotencyKey) > 128 {
		return nil, fmt.Errorf("product key and idempotency key are required")
	}
	tx, err := database.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	if existing, found, err := loadReservation(ctx, tx, params.UserID, params.IdempotencyKey); err != nil {
		return nil, err
	} else if found {
		existing.Idempotent = true
		switch existing.Status {
		case "completed":
			return existing, nil
		case "reserved":
			return existing, ErrSpendInProgress
		default:
			return existing, ErrSpendRefunded
		}
	}

	var product Product
	var metadataRaw string
	err = tx.QueryRowContext(ctx, `SELECT product_key,category,name_key,description_key,emoji,coins,enabled,sort_order,metadata::text
		FROM credit_products WHERE environment=$1 AND product_key=$2 AND enabled=true FOR SHARE`, params.Environment, params.ProductKey).Scan(
		&product.Key, &product.Category, &product.NameKey, &product.DescriptionKey, &product.Emoji,
		&product.Coins, &product.Enabled, &product.SortOrder, &metadataRaw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrProductNotFound
	}
	if err != nil {
		return nil, err
	}
	_ = json.Unmarshal([]byte(metadataRaw), &product.Metadata)

	var balance int
	if err := tx.QueryRowContext(ctx, `SELECT credits_balance FROM users WHERE id=$1 FOR UPDATE`, params.UserID).Scan(&balance); err != nil {
		return nil, err
	}
	if balance < product.Coins {
		return nil, ErrInsufficientCredit
	}
	newBalance := balance - product.Coins
	spendID := uuid.New().String()
	encodedMetadata, _ := json.Marshal(params.Metadata)
	if _, err := tx.ExecContext(ctx, `UPDATE users SET credits_balance=$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2`, newBalance, params.UserID); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO credit_spends(
		id,user_id,companion_id,product_key,coins,status,idempotency_key,reference_type,metadata)
		VALUES($1,$2,NULLIF($3,''),$4,$5,'reserved',$6,$7,$8)`, spendID, params.UserID,
		params.CompanionID, product.Key, product.Coins, params.IdempotencyKey, params.ReferenceType, encodedMetadata); err != nil {
		return nil, err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO credit_transactions(
		id,user_id,amount,balance_after,kind,description,platform,environment,spend_id)
		VALUES($1,$2,$3,$4,'consume',$5,$6,$7,$8)`, uuid.New().String(), params.UserID,
		-product.Coins, newBalance, "product:"+product.Key, params.Platform, params.Environment, spendID); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &Reservation{ID: spendID, Product: product, Balance: newBalance, Status: "reserved", Result: map[string]any{}}, nil
}

func Complete(ctx context.Context, database *sql.DB, spendID, referenceID string, result map[string]any) error {
	encoded, _ := json.Marshal(result)
	updated, err := database.ExecContext(ctx, `UPDATE credit_spends SET status='completed',reference_id=$2,result=$3,completed_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP
		WHERE id=$1 AND status='reserved'`, spendID, referenceID, encoded)
	if err != nil {
		return err
	}
	count, _ := updated.RowsAffected()
	if count != 1 {
		return fmt.Errorf("credit spend is not reservable")
	}
	return nil
}

func Refund(ctx context.Context, database *sql.DB, spendID, reason string) error {
	tx, err := database.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var userID, productKey, status, environment, platform string
	var coins int
	err = tx.QueryRowContext(ctx, `SELECT s.user_id,s.product_key,s.coins,s.status,u.environment,
		COALESCE((SELECT platform FROM credit_transactions WHERE spend_id=s.id ORDER BY created_at LIMIT 1),'system')
		FROM credit_spends s JOIN users u ON u.id=s.user_id WHERE s.id=$1 FOR UPDATE`, spendID).Scan(
		&userID, &productKey, &coins, &status, &environment, &platform)
	if err != nil {
		return err
	}
	if status == "refunded" {
		return nil
	}
	if status != "reserved" {
		return fmt.Errorf("completed credit spend cannot be refunded")
	}
	var balance int
	if err := tx.QueryRowContext(ctx, `UPDATE users SET credits_balance=credits_balance+$1,updated_at=CURRENT_TIMESTAMP WHERE id=$2 RETURNING credits_balance`, coins, userID).Scan(&balance); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE credit_spends SET status='refunded',failure_reason=$2,refunded_at=CURRENT_TIMESTAMP,updated_at=CURRENT_TIMESTAMP WHERE id=$1`, spendID, truncate(reason, 1000)); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO credit_transactions(
		id,user_id,amount,balance_after,kind,description,platform,environment,spend_id)
		VALUES($1,$2,$3,$4,'refund',$5,$6,$7,$8)`, uuid.New().String(), userID, coins, balance,
		"refund:"+productKey, platform, environment, spendID); err != nil {
		return err
	}
	return tx.Commit()
}

func loadReservation(ctx context.Context, tx *sql.Tx, userID, idempotencyKey string) (*Reservation, bool, error) {
	var output Reservation
	var metadataRaw, resultRaw string
	err := tx.QueryRowContext(ctx, `SELECT s.id,s.status,s.coins,COALESCE(s.result,'{}'::jsonb)::text,
		p.product_key,p.category,p.name_key,p.description_key,p.emoji,p.enabled,p.sort_order,p.metadata::text,
		u.credits_balance
		FROM credit_spends s JOIN users u ON u.id=s.user_id
		JOIN credit_products p ON p.environment=u.environment AND p.product_key=s.product_key
		WHERE s.user_id=$1 AND s.idempotency_key=$2`, userID, idempotencyKey).Scan(
		&output.ID, &output.Status, &output.Product.Coins, &resultRaw, &output.Product.Key,
		&output.Product.Category, &output.Product.NameKey, &output.Product.DescriptionKey,
		&output.Product.Emoji, &output.Product.Enabled, &output.Product.SortOrder, &metadataRaw, &output.Balance)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	_ = json.Unmarshal([]byte(metadataRaw), &output.Product.Metadata)
	_ = json.Unmarshal([]byte(resultRaw), &output.Result)
	return &output, true, nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanProduct(row rowScanner) (Product, error) {
	var product Product
	var metadataRaw string
	err := row.Scan(&product.Key, &product.Category, &product.NameKey, &product.DescriptionKey,
		&product.Emoji, &product.Coins, &product.Enabled, &product.SortOrder, &metadataRaw)
	if err != nil {
		return product, err
	}
	_ = json.Unmarshal([]byte(metadataRaw), &product.Metadata)
	return product, nil
}

func truncate(value string, limit int) string {
	value = strings.TrimSpace(value)
	if len(value) <= limit {
		return value
	}
	return value[:limit]
}

func StaleReservations(ctx context.Context, database *sql.DB, olderThan time.Duration) ([]string, error) {
	rows, err := database.QueryContext(ctx, `SELECT id FROM credit_spends WHERE status='reserved' AND created_at<$1`, time.Now().UTC().Add(-olderThan))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func RefundStale(ctx context.Context, database *sql.DB, olderThan time.Duration) error {
	ids, err := StaleReservations(ctx, database, olderThan)
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err := Refund(ctx, database, id, "experience timed out"); err != nil {
			return err
		}
	}
	return nil
}
