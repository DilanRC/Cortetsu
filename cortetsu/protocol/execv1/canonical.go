package execv1

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode/utf16"
)

const fingerprintDomain = "CORTETSU-IDEMPOTENCY-v1\n"

var resourceIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$`)

// validEscapedSurrogates rejects escaped unpaired UTF-16 surrogates. Go's
// encoding/json normally replaces malformed pairs with U+FFFD, which would
// silently change the semantic request fingerprint.
func validEscapedSurrogates(data []byte) bool {
	for i := 0; i < len(data); i++ {
		if data[i] != '"' {
			continue
		}
		i++
		for i < len(data) && data[i] != '"' {
			if data[i] != '\\' {
				i++
				continue
			}
			if i+1 >= len(data) {
				return false
			}
			if data[i+1] != 'u' {
				i++
				i++
				continue
			}
			if i+6 > len(data) {
				return false
			}
			value, err := strconv.ParseUint(string(data[i+2:i+6]), 16, 16)
			if err != nil {
				return false
			}
			if value >= 0xD800 && value <= 0xDBFF {
				if i+12 > len(data) || data[i+6] != '\\' || data[i+7] != 'u' {
					return false
				}
				next, err := strconv.ParseUint(string(data[i+8:i+12]), 16, 16)
				if err != nil || next < 0xDC00 || next > 0xDFFF {
					return false
				}
				i += 12
			} else {
				if value >= 0xDC00 && value <= 0xDFFF {
					return false
				}
				i += 6
			}
		}
		if i == len(data) {
			return false
		}
	}
	return true
}

// Canonicalize returns RFC 8785 (JCS) JSON for the supported I-JSON subset.
// It rejects duplicate keys, unpaired surrogates, non-finite binary64 numbers,
// negative zero, invalid UTF-8, extra documents and oversized payloads.
func Canonicalize(data []byte) ([]byte, error) {
	if !validEscapedSurrogates(data) {
		return nil, invalid()
	}
	var raw json.RawMessage
	if err := strictDecode(data, &raw); err != nil {
		return nil, err
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	var value any
	if err := d.Decode(&value); err != nil {
		return nil, invalid()
	}
	var b bytes.Buffer
	if err := appendJCS(&b, value); err != nil {
		return nil, err
	}
	return b.Bytes(), nil
}

func appendJSONString(b *bytes.Buffer, value string) {
	b.WriteByte('"')
	const hex = "0123456789abcdef"
	for _, r := range value {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\b':
			b.WriteString(`\b`)
		case '\f':
			b.WriteString(`\f`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		default:
			if r <= 0x1f {
				b.WriteString(`\u00`)
				b.WriteByte(hex[byte(r)>>4])
				b.WriteByte(hex[byte(r)&15])
			} else {
				b.WriteRune(r)
			}
		}
	}
	b.WriteByte('"')
}

func jcsNumber(n json.Number) (string, error) {
	f, err := strconv.ParseFloat(string(n), 64)
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) || (f == 0 && math.Signbit(f)) {
		return "", invalid()
	}
	if f == 0 {
		return "0", nil
	}
	if a := math.Abs(f); a >= 1e-6 && a < 1e21 {
		return strconv.FormatFloat(f, 'f', -1, 64), nil
	}
	scientific := strconv.FormatFloat(f, 'e', -1, 64)
	parts := strings.Split(scientific, "e")
	if len(parts) != 2 {
		return "", invalid()
	}
	exponent, err := strconv.Atoi(parts[1])
	if err != nil {
		return "", invalid()
	}
	if exponent >= 0 {
		return fmt.Sprintf("%se+%d", parts[0], exponent), nil
	}
	return fmt.Sprintf("%se%d", parts[0], exponent), nil
}

func appendJCS(b *bytes.Buffer, value any) error {
	switch v := value.(type) {
	case nil:
		b.WriteString("null")
	case bool:
		if v {
			b.WriteString("true")
		} else {
			b.WriteString("false")
		}
	case string:
		appendJSONString(b, v)
	case json.Number:
		n, err := jcsNumber(v)
		if err != nil {
			return err
		}
		b.WriteString(n)
	case []any:
		b.WriteByte('[')
		for i, item := range v {
			if i != 0 {
				b.WriteByte(',')
			}
			if err := appendJCS(b, item); err != nil {
				return err
			}
		}
		b.WriteByte(']')
	case map[string]any:
		keys := make([]string, 0, len(v))
		for key := range v {
			keys = append(keys, key)
		}
		slices.SortFunc(keys, func(a, z string) int {
			return slices.Compare(utf16.Encode([]rune(a)), utf16.Encode([]rune(z)))
		})
		b.WriteByte('{')
		for i, key := range keys {
			if i != 0 {
				b.WriteByte(',')
			}
			appendJSONString(b, key)
			b.WriteByte(':')
			if err := appendJCS(b, v[key]); err != nil {
				return err
			}
		}
		b.WriteByte('}')
	default:
		return invalid()
	}
	return nil
}

// FingerprintRequest derives the installation-scoped semantic identity for
// a mutating operation. request_id, session and deadline are deliberately not
// included, so reconnecting cannot change the identity of the operation.
// The journal implementing persistence, tombstones and replay protection must
// be written and validated before any caller is allowed to mutate resources.
func FingerprintRequest(r *Request, resourceID string) ([32]byte, error) {
	if r == nil || r.ExpectedRevision == nil || r.IdempotencyKey == "" || !resourceIDPattern.MatchString(resourceID) {
		return [32]byte{}, invalid()
	}
	body, err := Canonicalize(r.Arguments)
	if err != nil {
		return [32]byte{}, err
	}
	d := json.NewDecoder(bytes.NewReader(body))
	d.UseNumber()
	var arguments any
	if err := d.Decode(&arguments); err != nil {
		return [32]byte{}, invalid()
	}
	value := map[string]any{
		"protocol":          Protocol,
		"major":             json.Number(strconv.Itoa(Major)),
		"operation":         r.Operation,
		"resource_id":       resourceID,
		"expected_revision": json.Number(strconv.FormatUint(*r.ExpectedRevision, 10)),
		"body":              arguments,
	}
	var b bytes.Buffer
	if err := appendJCS(&b, value); err != nil {
		return [32]byte{}, err
	}
	return sha256.Sum256(append([]byte(fingerprintDomain), b.Bytes()...)), nil
}
