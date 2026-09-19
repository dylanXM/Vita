// Package mail sends outbound transactional email (currently: registration
// verification codes) over plain SMTP using only the standard library.
//
// When no SMTP host is configured (local dev), SendVerificationCode falls back
// to printing the code to the server log so the flow stays testable without a
// mailbox.
package mail

import (
	"crypto/tls"
	"fmt"
	"io"
	"mime/quotedprintable"
	"net"
	"net/smtp"
	"strconv"
	"strings"
)

// Config holds the SMTP settings loaded from environment variables
// (VITA_SMTP_*). A zero Host disables real sending.
type Config struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
	FromName string
}

// Enabled reports whether real sending is configured.
func (c *Config) Enabled() bool {
	return c.Host != ""
}

// SendVerificationCode emails the 6-digit code to to.
func (c *Config) SendVerificationCode(to, code string) error {
	if !c.Enabled() {
		fmt.Printf("[MAIL] SMTP not configured — verification code for %s: %s\n", to, code)
		return nil
	}

	client, w, err := c.openData(to)
	if err != nil {
		return err
	}
	defer client.Close()

	from := c.From
	if c.FromName != "" {
		from = fmt.Sprintf("%s <%s>", c.FromName, c.From)
	}
	if err := writeMessage(w, from, to, code); err != nil {
		return fmt.Errorf("smtp write: %w", err)
	}
	if err := client.Quit(); err != nil {
		return fmt.Errorf("smtp quit: %w", err)
	}
	return nil
}

// openData dials the SMTP server (implicit TLS on port 465, STARTTLS
// otherwise), authenticates and opens the data stream for a message addressed
// to to.
func (c *Config) openData(to string) (*smtp.Client, io.WriteCloser, error) {
	addr := net.JoinHostPort(c.Host, strconv.Itoa(c.Port))
	tlsCfg := &tls.Config{ServerName: c.Host}

	var client *smtp.Client
	var err error
	if c.Port == 465 {
		// Implicit TLS: wrap the TCP connection ourselves, then hand it to
		// smtp.NewClient (net/smtp has no DialTLS helper).
		conn, err := tls.Dial("tcp", addr, tlsCfg)
		if err != nil {
			return nil, nil, fmt.Errorf("smtp connect: %w", err)
		}
		if client, err = smtp.NewClient(conn, c.Host); err != nil {
			conn.Close()
			return nil, nil, fmt.Errorf("smtp handshake: %w", err)
		}
	} else {
		client, err = smtp.Dial(addr)
	}
	if err != nil {
		return nil, nil, fmt.Errorf("smtp connect: %w", err)
	}
	fail := func(err error) (*smtp.Client, io.WriteCloser, error) {
		client.Close()
		return nil, nil, err
	}

	if c.Port != 465 {
		if err := client.StartTLS(tlsCfg); err != nil {
			return fail(fmt.Errorf("starttls: %w", err))
		}
	}
	if c.Username != "" {
		if err := client.Auth(smtp.PlainAuth("", c.Username, c.Password, c.Host)); err != nil {
			return fail(fmt.Errorf("smtp auth: %w", err))
		}
	}
	if err := client.Mail(c.From); err != nil {
		return fail(fmt.Errorf("smtp mail: %w", err))
	}
	if err := client.Rcpt(to); err != nil {
		return fail(fmt.Errorf("smtp rcpt: %w", err))
	}
	w, err := client.Data()
	if err != nil {
		return fail(fmt.Errorf("smtp data: %w", err))
	}
	return client, w, nil
}

// writeMessage emits headers + body (HTML with a plain-text fallback).
func writeMessage(w io.Writer, from, to, code string) error {
	var b strings.Builder
	fmt.Fprintf(&b, "From: %s\r\n", from)
	fmt.Fprintf(&b, "To: %s\r\n", to)
	b.WriteString("Subject: Your Vita verification code\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: multipart/alternative; boundary=\"alt-0\"\r\n")
	b.WriteString("\r\n")

	plain := fmt.Sprintf("Your Vita verification code is %s. It expires in 5 minutes. If you did not request it, you can ignore this email.\n", code)
	b.WriteString("--alt-0\r\n")
	b.WriteString("Content-Type: text/plain; charset=\"utf-8\"\r\n")
	b.WriteString("Content-Transfer-Encoding: quoted-printable\r\n\r\n")
	writeQuotedPrintable(&b, plain)
	b.WriteString("\r\n--alt-0\r\n")
	b.WriteString("Content-Type: text/html; charset=\"utf-8\"\r\n")
	b.WriteString("Content-Transfer-Encoding: quoted-printable\r\n\r\n")
	writeQuotedPrintable(&b, buildCodeEmail(code))
	b.WriteString("\r\n--alt-0--\r\n")

	_, err := io.WriteString(w, b.String())
	return err
}

// buildCodeEmail renders the minimal brand-consistent message body.
func buildCodeEmail(code string) string {
	return `<!DOCTYPE html>
<html>
  <body style="margin:0;padding:0;background:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f5;padding:32px 0;">
      <tr>
        <td align="center">
          <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;padding:32px;">
            <tr>
              <td>
                <p style="margin:0 0 8px;font-size:18px;font-weight:600;color:#191919;">Vita</p>
                <p style="margin:0 0 24px;font-size:14px;color:#888888;">A companion who lives somewhere else</p>
                <p style="margin:0 0 16px;font-size:14px;color:#191919;">Your verification code</p>
                <p style="margin:0 0 16px;font-size:32px;font-weight:700;letter-spacing:6px;color:#07c160;text-align:center;">` + code + `</p>
                <p style="margin:0 0 8px;font-size:12px;color:#888888;">It expires in 5 minutes. If you did not request it, you can ignore this email.</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`
}

// writeQuotedPrintable appends s encoded as quoted-printable.
func writeQuotedPrintable(b *strings.Builder, s string) {
	r := quotedprintable.NewWriter(b)
	io.WriteString(r, s)
	r.Close()
}
