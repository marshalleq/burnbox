# Burnbox

**Self-hosted file transfer with time-limited drops.** Upload files, share a link, let the expiry do the work — no chasing recipients, no orphaned files filling your disk.

A self-hosted alternative to WeTransfer, Dropbox file requests, and the late Firefox Send.

## Why time-limited?

Recipients rarely confirm a download. Burnbox doesn't ask: every drop has an expiry, so files clean themselves up. One less inbox to manage and a disk that doesn't fill with stale archives.

## Features

* No accounts, no logins
* Resumable up- and downloads via [tus.io](https://tus.io) — handles big files and flaky connections
* Per-bucket expiry and one-time-download mode
* Password-protected download lists (Argon2 hashed, AES bucket encryption)
* ZIP archive download for whole buckets (offered when a bucket has more than one file)
* Direct per-file download button
* Mobile-friendly Vue.js frontend (~100k gzipped)
* `/admin` page (gated by `BURNBOX_ADMIN_PASS`)
* Modern runtime: Node 26 (LTS), native Web Crypto, Argon2 password hashing

## Quickstart

### Docker

A multi-architecture image (amd64 and arm64) is published to `ghcr.io/marshalleq/burnbox`: `latest` follows `master`, and release tags follow `v*` tags. To build it yourself instead:

```bash
git clone https://github.com/marshalleq/burnbox.git
cd burnbox
docker build -t burnbox .
docker run -d --name burnbox -p 3000:3000 \
  -e BURNBOX_ADMIN_PASS=secret \
  -v $PWD/data:/data \
  burnbox
# data volume needs UID 1000
sudo chown -R 1000 $PWD/data
```

### Node (manual)

Requires Node ≥ 26 (the version in `.nvmrc`).

```bash
git clone https://github.com/marshalleq/burnbox.git
cd burnbox
cd app && npm install && npm run build && cd ..
npm install
NODE_ENV=production npm start
```

## Configuration

Environment variables:

* `BURNBOX_UPLOAD_DIR` — upload directory (defaults to `./data`)
* `BURNBOX_UPLOAD_PASS` — gate uploads behind a password (recommended for public exposure)
* `BURNBOX_ADMIN_PASS` — enable `/admin` and set its password
* `DEBUG=burnbox:*` — enable debug logging

You can also drop a `config.production.js` (or `config.<NODE_ENV>.js`) next to `config.js` to override defaults — see `config.dev.js` for an example.

## Customization

`public/pug/upload.pug` and `download.pug` are the entry templates. Add your logo/styles there.

## Limitations

* No browser-side end-to-end payload encryption (yet)
* `Download all as ZIP` does not support resuming the download

## Development, checks and automatic updates

The repository looks after its own dependencies and only asks for a human when a decision is needed.

**Checks.** Every push and pull request runs one job, `ci` (in `.github/workflows/ci.yml`), before anything else:

1. Lints the workflow files (`actionlint`).
2. Installs the server and frontend dependencies from their lockfiles.
3. Syntax-checks every server file.
4. Builds the frontend.
5. Smoke-tests the server: starts it, loads each page, then uploads a file over tus and downloads it again (`.github/scripts/smoke-test.sh`).

The Docker image is only built and pushed if `ci` passes. `master` is protected: the `ci / ci` check must pass before a change merges, and force-pushes and deletion are blocked. Repository admins are not forced to follow the check, so a broken `master` can still be repaired directly.

To run the same checks locally, use the Node version in `.nvmrc`, then: `npm ci && (cd app && npm ci && npm run build) && .github/scripts/smoke-test.sh`.

**Automatic updates.** Dependabot (`.github/dependabot.yml`) checks both npm folders (`/` and `/app`), the Dockerfile and the GitHub Actions each week, and raises security fixes as soon as an advisory is published.

* Minor and patch updates are grouped into one pull request per area. They are merged automatically once `ci` passes (`.github/workflows/dependabot-automerge.yml`).
* Major updates are never merged automatically. They stay open as pull requests until someone has tested and decided on them.
* The image is rebuilt from scratch every Sunday so that base-image security fixes are picked up even when no code has changed.

**Pinned or overridden dependencies.** These exist only to clear security advisories in build-time tooling. Remove them once the upstream packages catch up.

| Package | Override | Reason |
|---|---|---|
| `sockjs` (via `webpack-dev-server`) | `uuid ^11.1.1` | Old `uuid` copy has an advisory; development server only. |
| `@vue/component-compiler-utils` (via `vue-loader`) | `postcss ^8.5.32` | Old `postcss` copy has an advisory; build time only. |

**Known open item.** `vue-template-compiler` has an advisory with no upstream fix because Vue 2 is end of life. It is used at build time only and is not part of the shipped image.

## License

[BSD-2-Clause](LICENSE)
