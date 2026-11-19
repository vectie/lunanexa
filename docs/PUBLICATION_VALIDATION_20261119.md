# Publication validation — 19 November 2026

The pending platform documentation, video transport fixes, teaching studio,
public site sources and operational utilities were published in separate
commits. Local `output/`, `tmp/` and Python caches remain excluded; deployment
captures and image layers were not added to Git.

Validation in this publication pass:

- `moon info`, `moon fmt` and `moon check --target native --deny-warn` passed.
- `node --test docs-site/*.test.mjs`: 70 passed, zero failed, one existing
  browser integration test skipped.
- `test_video_transport.py`: 13 passed using Python with aiohttp installed.
- The source credential scan found environment-variable references and test
  fixtures, without private keys or live API token literals.

These checks cover source compilation, content consistency and transport
regressions. They do not establish a fresh browser end-to-end run, GPU service
qualification or a live deployment. The operational scripts are archived source;
publishing them does not execute them or restart services.
