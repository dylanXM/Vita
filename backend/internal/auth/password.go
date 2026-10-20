// Package auth holds the credential primitives shared by the startup admin
// seeding (internal/db) and the login handlers (internal/handler).
package auth

import "golang.org/x/crypto/bcrypt"

// HashPassword returns a bcrypt hash for storage in users.password_hash.
func HashPassword(password string) (string, error) {
	hashed, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(hashed), err
}

// VerifyPassword reports whether password matches the stored bcrypt hash.
// Accounts that only signed in with a verification code have an empty hash and
// can never match, so a code-only account cannot be taken over by a blank
// password.
func VerifyPassword(hash, password string) bool {
	if hash == "" || password == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
