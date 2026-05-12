---
name: security-and-hardening
description: Hardens code against vulnerabilities. Use when handling user input, authentication, data storage, or external integrations. Use when building any feature that accepts untrusted data, manages user sessions, or interacts with third-party services.
---

# Security and Hardening

Treat every external input as hostile, every secret as sacred, every authorization check as mandatory.

## The Three-Tier Boundary System

### Always Do (No Exceptions)

- Validate all external input at the system boundary
- Parameterize all database queries — never concatenate user input
- Encode output to prevent XSS (use framework auto-escaping, don't bypass it)
- Use HTTPS for all external communication
- Hash passwords with bcrypt/scrypt/argon2
- Set security headers (CSP, HSTS, X-Frame-Options, X-Content-Type-Options)
- Use httpOnly, secure, sameSite cookies for sessions
- Run dependency audit before every release

### Ask First (Requires Human Approval)

- Adding or changing authentication flows
- Storing new categories of sensitive data (PII, payment info)
- Adding external service integrations
- Changing CORS configuration
- Adding file upload handlers
- Modifying rate limiting or throttling
- Granting elevated permissions or roles

### Never Do

- Commit secrets to version control
- Log sensitive data (passwords, tokens, full credit card numbers)
- Trust client-side validation as a security boundary
- Disable security headers for convenience
- Use `eval()` or `innerHTML` with user-provided data
- Store sessions in client-accessible storage (localStorage for auth tokens)
- Expose stack traces or internal error details to users

## Security Review Checklist

### Authentication
- [ ] Passwords hashed with bcrypt/scrypt/argon2 (salt rounds >= 12)
- [ ] Session tokens are httpOnly, secure, sameSite
- [ ] Login has rate limiting
- [ ] Password reset tokens expire

### Authorization
- [ ] Every endpoint checks user permissions
- [ ] Users can only access their own resources
- [ ] Admin actions require admin role verification

### Input
- [ ] All user input validated at the boundary
- [ ] SQL queries are parameterized
- [ ] HTML output is encoded/escaped

### Data
- [ ] No secrets in code or version control
- [ ] Sensitive fields excluded from API responses
- [ ] PII encrypted at rest (if applicable)

### Infrastructure
- [ ] Security headers configured
- [ ] CORS restricted to known origins
- [ ] Dependencies audited for vulnerabilities
- [ ] Error messages don't expose internals

## Red Flags

- User input passed directly to database queries, shell commands, or HTML rendering
- Secrets in source code or commit history
- API endpoints without authentication or authorization checks
- Missing CORS configuration or wildcard (`*`) origins
- No rate limiting on authentication endpoints
- Stack traces or internal errors exposed to users
- Dependencies with known critical vulnerabilities
