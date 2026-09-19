package db

import (
	"fmt"

	"github.com/google/uuid"

	"vita/internal/auth"
)

// EnsureAdmin makes sure the configured administrator accounts exist so a
// freshly initialised database can be signed into.
//
//   - email/password create (or repair) one account with the admin role and a
//     bcrypt password hash. An account that already has a hash keeps it, so
//     restarting the server never resets a password an administrator changed.
//   - extraEmails are promoted to the admin role in place. They keep whatever
//     credential they already had, which is how an existing verification-code
//     account is granted dashboard access without inventing a password for it.
func EnsureAdmin(email, password string, extraEmails []string, env string) error {
	if email != "" && password != "" {
		if err := upsertAdminWithPassword(email, password, env); err != nil {
			return err
		}
	}

	for _, e := range extraEmails {
		if e == "" || e == email {
			continue
		}
		if err := promoteAdmin(e); err != nil {
			return err
		}
	}
	return nil
}

// env is stamped onto newly created administrator rows; pre-existing rows
// keep whatever flag they already carry (the DO UPDATE clause never touches
// the environment column).
func upsertAdminWithPassword(email, password, env string) error {
	hash, err := auth.HashPassword(password)
	if err != nil {
		return fmt.Errorf("hash password for %s: %w", email, err)
	}

	_, err = Get().Exec(`
		INSERT INTO users (id, email, role_id, password_hash, environment)
		VALUES ($1, $2, 'admin', $3, $4)
		ON CONFLICT (email) DO UPDATE
		SET role_id = 'admin',
		    updated_at = CURRENT_TIMESTAMP,
		    password_hash = CASE
		        WHEN COALESCE(users.password_hash, '') = '' THEN EXCLUDED.password_hash
		        ELSE users.password_hash
		    END`,
		uuid.New().String(), email, hash, env)
	if err != nil {
		return fmt.Errorf("seed admin %s: %w", email, err)
	}

	fmt.Printf("admin account ready: %s\n", email)
	return nil
}

func promoteAdmin(email string) error {
	res, err := Get().Exec(
		`UPDATE users SET role_id = 'admin', updated_at = CURRENT_TIMESTAMP WHERE email = $1`,
		email)
	if err != nil {
		return fmt.Errorf("promote admin %s: %w", email, err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		fmt.Printf("warning: VITA_ADMIN_EMAILS lists %s but no such account exists yet\n", email)
	}
	return nil
}
