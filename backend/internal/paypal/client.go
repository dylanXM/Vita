// Package paypal implements the server-only PayPal REST boundary.
package paypal

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Client struct {
	ClientID, Secret, BaseURL string
	HTTP                      *http.Client
}

func (c Client) endpoint() string {
	if c.BaseURL != "" {
		return c.BaseURL
	}
	return "https://api-m.sandbox.paypal.com"
}
func (c Client) httpClient() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 25 * time.Second}
}
func (c Client) Request(ctx context.Context, method, path, requestID string, body, result any) error {
	tokenReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint()+"/v1/oauth2/token", strings.NewReader("grant_type=client_credentials"))
	if err != nil {
		return err
	}
	tokenReq.SetBasicAuth(c.ClientID, c.Secret)
	tokenReq.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := c.httpClient().Do(tokenReq)
	if err != nil {
		return fmt.Errorf("paypal authorization unavailable: %w", err)
	}
	var token struct {
		AccessToken string `json:"access_token"`
	}
	err = json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&token)
	response.Body.Close()
	if err != nil || response.StatusCode != 200 || token.AccessToken == "" {
		return fmt.Errorf("paypal authorization failed (%d)", response.StatusCode)
	}
	var encoded []byte
	if body != nil {
		encoded, err = json.Marshal(body)
		if err != nil {
			return err
		}
	}
	req, err := http.NewRequestWithContext(ctx, method, c.endpoint()+path, bytes.NewReader(encoded))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Prefer", "return=representation")
	if requestID != "" {
		req.Header.Set("PayPal-Request-Id", requestID)
	}
	response, err = c.httpClient().Do(req)
	if err != nil {
		return fmt.Errorf("paypal request unavailable: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("paypal request failed (%d)", response.StatusCode)
	}
	if result == nil || response.StatusCode == 204 {
		return nil
	}
	return json.NewDecoder(io.LimitReader(response.Body, 2<<20)).Decode(result)
}
func ApprovalURL(links []Link) string {
	for _, link := range links {
		if link.Rel != "approve" && link.Rel != "payer-action" {
			continue
		}
		u, err := url.Parse(link.Href)
		if err == nil && u.Scheme == "https" && (u.Host == "www.sandbox.paypal.com" || u.Host == "www.paypal.com") {
			return u.String()
		}
	}
	return ""
}

type Link struct {
	Rel  string `json:"rel"`
	Href string `json:"href"`
}
type Amount struct {
	Currency string `json:"currency_code"`
	Value    string `json:"value"`
}
type Capture struct {
	ID     string `json:"id"`
	Status string `json:"status"`
	Amount Amount `json:"amount"`
}
type Order struct {
	ID     string `json:"id"`
	Status string `json:"status"`
	Links  []Link `json:"links"`
	Units  []struct {
		CustomID string `json:"custom_id"`
		Amount   Amount `json:"amount"`
		Payments struct {
			Captures []Capture `json:"captures"`
		} `json:"payments"`
	} `json:"purchase_units"`
}
type Subscription struct {
	ID       string `json:"id"`
	PlanID   string `json:"plan_id"`
	CustomID string `json:"custom_id"`
	Status   string `json:"status"`
	Links    []Link `json:"links"`
	Billing  struct {
		NextBillingTime time.Time `json:"next_billing_time"`
		LastPayment     struct {
			Time   time.Time `json:"time"`
			Amount Amount    `json:"amount"`
		} `json:"last_payment"`
	} `json:"billing_info"`
}
