---
name: GitHub access fallback
description: Standard Git and authenticated GitHub CLI can work when connector credentials are unavailable.
---

If the GitHub integration is reported authorized but `listConnections` yields no
usable connection, do not assume repository pushes are impossible. Standard Git
operations may independently work through Replit's secure GitHub proxy.

**Why:** Connector-based repository listing was unavailable in this project, but
ordinary `git ls-remote` and a non-force `git push` successfully accessed the
user's chosen repository without reading or supplying credentials. Authenticated
`gh api` and `gh secret set` also worked independently when the connector withheld
credentials, including administrator operations on protected environment secrets.

**How to apply:** When the user has authorized a push and supplied a repository,
try ordinary Git access before declaring a blocker. Never inspect tokens or
credential helpers. Preserve unrelated remote history and source; use a
non-force push. Also try an ordinary authenticated `gh api` request when GitHub API
access is needed; never inspect its token or credential storage. Connector access,
Git transport, and GitHub CLI authentication are distinct.
