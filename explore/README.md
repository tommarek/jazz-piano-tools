# Exploratory harness

Not part of the test suite — tools for looking at the app rather than asserting
about it.

- `seed.mjs <db> [history|gate-ready]` — fills a database with plausible
  practice history so the stats screens have something real to draw.
- `drive.mjs` — walks every screen and flow, screenshotting each state and
  recording console errors, failed requests and horizontal overflow.

Both expect the app served at `http://127.0.0.1:4173`:

```bash
VITE_VT_TEST=1 npm run build && npx sirv-cli build --single --host 127.0.0.1 --port 4173
npx vite-node explore/drive.mjs
```
