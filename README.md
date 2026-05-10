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
* ZIP / TAR.GZ archive download for whole buckets
* Direct per-file download button
* Mobile-friendly Vue.js frontend (~100k gzipped)
* `/admin` page (gated by `BURNBOX_ADMIN_PASS`)
* Modern runtime: Node 24, native Web Crypto, Argon2 password hashing

## Quickstart

### Docker

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

Requires Node ≥ 24.

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

## License

[BSD-2-Clause](LICENSE)
