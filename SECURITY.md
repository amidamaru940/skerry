# Security

Skerry reads the clipboard and your screenshots, so we take reports seriously.

## Reporting a vulnerability

Please report it **privately** through [GitHub's private vulnerability reporting](https://github.com/amidamaru940/skerry/security/advisories/new), not in a public issue. Include the Skerry and macOS versions, what an attacker could do, and steps to reproduce.

You will get an answer within a week. Fixes go out in the next release, and you will be credited if you like.

## Supported versions

Only the latest release gets security fixes.

## What Skerry does by default

- No network requests and no listening ports. Every address in the code is listed in `tests/network_allowlist.txt`, and a test enforces it.
- Clipboard history lives in memory only, unless you turn on saving it.
- Concealed clipboard items (from password managers) and apps you exclude are never recorded.
