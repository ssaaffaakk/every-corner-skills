# Example: room report

> Illustrative example. The project, file names and line numbers are made up to show the format. A real report cites your actual code.

**Request from the human:** "Add rate limiting to the login endpoint."

---

## Room report

**Task (my understanding):** Limit how many times one person can try to log in within a short time, so passwords cannot be guessed by brute force.
**Done looks like:** The 6th failed login from the same IP within 10 minutes gets a "too many attempts" response, and the existing login tests still pass.

**What I found**
- Login is handled in one place, `POST /login` in `src/routes/auth.ts:31`. It is the only route that checks passwords.
- The app already uses Redis for sessions (`src/lib/redis.ts:8`), so a counter store is available without new infrastructure.
- A rate-limit helper already exists, `src/middleware/rateLimit.ts:12`, but it is only used on `/signup`. Reusing it matches the project's pattern.
- Tests for login live in `test/auth.test.ts`; they currently pass (ran `npm test`, 42 passed).

**Surprises / under the rug**
- `rateLimit.ts:20` has a comment `// TODO: trusts X-Forwarded-For`. Behind our load balancer that header can be spoofed, so a naive per-IP limit could be bypassed (`git blame` shows this was left on purpose until the proxy config was fixed).
- `src/config/env.ts:14` reads `RATE_LIMIT_WINDOW`, but `.env.example` does not list it. A new developer would not know it exists.

**Assumed, not verified**
- That production runs one Redis shared by all app servers -> *check the deploy config, or ask whoever owns infra.*
- That 5 attempts / 10 minutes is the right limit -> *product decision.*

**Plan (plain language, in order)**
1. Reuse the existing rate-limit helper on the login route, with a limit of 5 failed attempts per 10 minutes.
2. Make the limit count only *failed* logins, so normal users are not punished.
3. Read the client address in a way that cannot be faked through the header (fixing the TODO), or limit per account name as well as per address.
4. Add two tests: the 6th attempt is blocked, and a successful login is not counted.
5. Add the missing setting to `.env.example`.

**Risk and undo**
- Risk: locking out real users behind a shared office network. Mitigation: also key on account name, and keep the window short.
- Undo: all changes are in 4 files and can be reverted with one `git revert`.

**Questions that change the plan**
1. Is 5 attempts / 10 minutes OK? *Default if you don't answer: yes.*
2. Is the load balancer under our control, so we can trust its forwarded address? *Default: no, so I will limit per account name too.*

---

### Why this report works

| Part | What it prevented |
|---|---|
| Found the existing helper | Writing a second, inconsistent rate limiter |
| Read the `TODO` and `git blame` | Shipping a limit that can be bypassed with one header |
| Marked "assumed" items | Presenting a guess about production as fact |
| Defaults on the questions | Blocking the human; they can answer "go" |
