---
name: security-review
description: >
  Reviews code for exploitable vulnerabilities and reports only high-confidence
  findings backed by a traced data flow. Use when asked for a security review,
  vulnerability check, OWASP review, or to audit code for injection, XSS,
  authentication, authorization or cryptography issues. Not for GitHub Actions
  workflows (use `gha-security-review`) or general code review (use
  `code-review`).
allowed-tools: Read, Grep, Glob, Bash, Task
license: OWASP-derived (see THIRD-PARTY-NOTICES.md)
source: https://github.com/getsentry/skills/tree/main/skills/security-review
metadata:
  category: preference

---

<!--
Reference material based on OWASP Cheat Sheet Series (CC BY-SA 4.0)
https://cheatsheetseries.owasp.org/
-->

# Security Review

Identify exploitable security vulnerabilities in code. Report only **HIGH CONFIDENCE** findings—clear vulnerable patterns with attacker-controlled input.

## Scope: Research vs. Reporting

- **Report on**: only the specific file, diff, or code the user provided
- **Research**: the callers, validation, configuration and trust boundaries needed to establish exploitability. Go as broad as the evidence requires; do not survey unrelated code.

Before flagging an issue, trace:
- Where does this input actually come from? (data flow)
- Is there validation or sanitization elsewhere?
- How is this configured? (settings, config files, middleware)
- What framework protections exist?

Do not report issues based solely on pattern matching. Investigate first, then report only what you're confident is exploitable.

## Confidence Levels

| Level | Criteria | Action |
|-------|----------|--------|
| **HIGH** | Vulnerable pattern + attacker-controlled input confirmed | Report with severity |
| **MEDIUM** | Vulnerable pattern, input source unclear | Note as "Needs verification" |
| **LOW** | Theoretical, best practice, defense-in-depth | Do not report |

## Do Not Flag

### General Rules
- Test files (unless explicitly reviewing test security)
- Dead code, commented code, documentation strings
- Patterns using constants or server-controlled values: Django settings, environment variables, config files, framework constants, hardcoded values. Operators set these; attackers do not.
- Code paths that require prior authentication to reach (note the auth requirement instead)

### Framework-Mitigated Patterns
Check language guides before flagging. Common false positives:

| Pattern | Why It's Usually Safe |
|---------|----------------------|
| Django `{{ variable }}` | Auto-escaped by default |
| React `{variable}` | Auto-escaped by default |
| Vue `{{ variable }}` | Auto-escaped by default |
| `User.objects.filter(id=input)` | ORM parameterizes queries |
| `cursor.execute("...%s", (input,))` | Parameterized query |
| `innerHTML = "<b>Loading...</b>"` | Constant string, no user input |

**Only flag these when:**
- Django: `{{ var|safe }}`, `{% autoescape off %}`, `mark_safe(user_input)`
- React: `dangerouslySetInnerHTML={{__html: userInput}}`
- Vue: `v-html="userInput"`
- ORM: `.raw()`, `.extra()`, `RawSQL()` with string interpolation

## Review Process

### 1. Detect Context

What type of code am I reviewing? Load the matching files from `references/`:

| Code Type | Load These References |
|-----------|----------------------|
| API endpoints, routes | `authorization.md`, `authentication.md`, `injection.md` |
| Frontend, templates | `xss.md`, `csrf.md` |
| File handling, uploads | `file-security.md` |
| Crypto, secrets, tokens | `cryptography.md`, `data-protection.md` |
| Data serialization | `deserialization.md` |
| External requests | `ssrf.md` |
| Business workflows | `business-logic.md` |
| GraphQL, REST design | `api-security.md` |
| WebSockets, LLM or agent input, prototype pollution | `modern-threats.md` |
| Config, headers, CORS | `misconfiguration.md` |
| CI/CD, dependencies | `supply-chain.md` |
| Error handling | `error-handling.md` |
| Audit, logging | `logging.md` |

### 2. Load Language Guide

Based on file extension or imports:

| Indicators | Guide |
|------------|-------|
| `.py`, `django`, `flask`, `fastapi` | `languages/python.md` |
| `.js`, `.ts`, `express`, `react`, `vue`, `next` | `languages/javascript.md` |

Other languages have no guide here: apply the references above and the framework's own safe-API conventions.

### 3. Load Infrastructure Guide (if applicable)

| File Type | Guide |
|-----------|-------|
| `Dockerfile`, `.dockerignore` | `infrastructure/docker.md` |

Kubernetes, Terraform and cloud configs have no guide here. GitHub Actions workflows go to `gha-security-review`.

### 4. Verify Exploitability

For each potential finding, confirm:

**Is the input attacker-controlled?**

| Attacker-Controlled (Investigate) | Server-Controlled (Usually Safe) |
|-----------------------------------|----------------------------------|
| `request.GET`, `request.POST`, `request.args` | `settings.X`, `app.config['X']` |
| `request.json`, `request.data`, `request.body` | `os.environ.get('X')` |
| `request.headers` (most headers) | Hardcoded constants |
| `request.cookies` (unsigned) | Internal service URLs from config |
| URL path segments: `/users/<id>/` | Database content from admin/system |
| File uploads (content and names) | Signed session data |
| Database content from other users | Framework settings |
| WebSocket messages | |

**Does the framework mitigate this?**
- Check language guide for auto-escaping, parameterization
- Check for middleware/decorators that sanitize

**Is there validation upstream?**
- Input validation before this code
- Sanitization libraries (DOMPurify, bleach, etc.)

Report only what you have confirmed is exploitable after research. Skip theoretical issues.

---

## Severity Classification

| Severity | Impact | Examples |
|----------|--------|----------|
| **Critical** | Direct exploit, severe impact, no auth required | RCE, SQL injection to data, auth bypass, hardcoded secrets |
| **High** | Exploitable with conditions, significant impact | Stored XSS, SSRF to metadata, IDOR to sensitive data |
| **Medium** | Specific conditions required, moderate impact | Reflected XSS, CSRF on state-changing actions, path traversal |
| **Low** | Defense-in-depth, minimal direct impact | Missing headers, verbose errors, weak algorithms in non-critical context |

---

## Quick Patterns Reference

These patterns are candidates, not findings. Confirm attacker-controlled input (Step 4) before reporting, except for exposed secrets.

### Investigate first: likely Critical
```
eval(user_input)           # Any language
exec(user_input)           # Any language
pickle.loads(user_data)    # Python
yaml.load(user_data)       # Python (not safe_load)
unserialize($user_data)    # PHP
deserialize(user_data)     # Java ObjectInputStream
shell=True + user_input    # Python subprocess
child_process.exec(user)   # Node.js
```

### Investigate first: likely High
```
innerHTML = userInput              # DOM XSS
dangerouslySetInnerHTML={user}     # React XSS
v-html="userInput"                 # Vue XSS
f"SELECT * FROM x WHERE {user}"    # SQL injection
`SELECT * FROM x WHERE ${user}`    # SQL injection
os.system(f"cmd {user_input}")     # Command injection
```

### Exposed secrets: report immediately when the literal is a real credential
```
password = "hardcoded"
api_key = "sk-..."
AWS_SECRET_ACCESS_KEY = "..."
private_key = "-----BEGIN"
```

### Check context first
```
# SSRF - only if the URL is user input, not settings/config
requests.get(request.GET['url'])     # FLAG: User-controlled URL
requests.get(settings.API_URL)       # SAFE: Server-controlled config
requests.get(f"{settings.BASE}/{x}") # CHECK: Is 'x' user input?

# Path traversal - only if the path is user input
open(request.GET['file'])            # FLAG: User-controlled path
open(settings.LOG_PATH)              # SAFE: Server-controlled config
open(f"{BASE_DIR}/{filename}")       # CHECK: Is 'filename' user input?

# Open redirect - only if the URL is user input
redirect(request.GET['next'])        # FLAG: User-controlled redirect
redirect(settings.LOGIN_URL)         # SAFE: Server-controlled config

# Weak crypto - only if used for security purposes
hashlib.md5(file_content)            # SAFE: File checksums, caching
hashlib.md5(password)                # FLAG: Password hashing
random.random()                      # SAFE: Non-security uses (UI, sampling)
random.random() for token            # FLAG: Security tokens need secrets module
```

---

## Output Format

````markdown
## Security Review: [File/Component Name]

### Summary
- **Findings**: X (Y Critical, Z High, ...)
- **Risk Level**: Critical/High/Medium/Low
- **Confidence**: High/Mixed

### Findings

#### [VULN-001] [Vulnerability Type] (Severity)
- **Location**: `file.py:123`
- **Confidence**: High
- **Issue**: [What the vulnerability is]
- **Impact**: [What an attacker could do]
- **Evidence**:
  ```python
  [Vulnerable code snippet]
  ```
- **Fix**: [How to remediate]

### Needs Verification

#### [VERIFY-001] [Potential Issue]
- **Location**: `file.py:456`
- **Question**: [What needs to be verified]
````

If no vulnerabilities found, state: "No high-confidence vulnerabilities identified."
