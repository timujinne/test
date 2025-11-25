# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in Binance Trading System, please report it responsibly.

### How to Report

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please email us directly at: **timujeen@gmail.com**

Include the following information in your report:
- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Any suggested fixes (optional)

### What to Expect

1. **Acknowledgment**: We will acknowledge receipt of your report within 48 hours
2. **Assessment**: We will assess the vulnerability and determine its severity within 7 days
3. **Fix Timeline**: Critical vulnerabilities will be addressed within 14 days
4. **Disclosure**: We will coordinate with you on public disclosure timing

### Scope

The following are in scope for security reports:

- **Authentication/Authorization** bypass
- **API key exposure** or leakage
- **Encryption weaknesses** in credential storage
- **SQL injection** or database vulnerabilities
- **Cross-site scripting (XSS)** in LiveView components
- **Remote code execution**
- **Denial of service** vulnerabilities
- **Trading logic exploits** that could cause financial loss

### Out of Scope

- Issues in dependencies (please report to the respective maintainers)
- Social engineering attacks
- Physical attacks
- Issues requiring physical access to user's device
- Binance API vulnerabilities (please report to Binance directly)

## Security Best Practices for Users

### API Key Security

1. **Never commit API keys** to version control
2. **Use testnet** for development and testing
3. **Enable IP whitelist** on Binance for production keys
4. **Disable withdrawal permissions** on API keys
5. **Rotate API keys** regularly (every 90 days recommended)
6. **Use environment variables** for all secrets

### Deployment Security

1. **Always use HTTPS** in production
2. **Keep dependencies updated** (`mix hex.outdated`)
3. **Run security audits** (`mix hex.audit`)
4. **Enable database SSL** in production
5. **Use strong SECRET_KEY_BASE** (minimum 64 characters)
6. **Monitor logs** for suspicious activity

### Database Security

1. **Use strong PostgreSQL passwords**
2. **Limit database user permissions**
3. **Enable SSL for database connections**
4. **Regular database backups** (encrypted)
5. **Don't expose database ports** publicly

## Encryption Details

This project uses industry-standard encryption:

- **API Keys**: AES-256-GCM encryption via Cloak
- **Passwords**: Argon2 hashing
- **API Signatures**: HMAC-SHA256

## Acknowledgments

We appreciate the security research community. Reporters who follow responsible disclosure will be acknowledged in our release notes (with permission).

---

Thank you for helping keep Binance Trading System secure!
