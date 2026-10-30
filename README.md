# Burnbox

**Send big files to clients with a link that deletes itself.** Self-hosted, no sign-up for the people you send to, resumable, and as fast as your own connection.

## Why Burnbox exists

Sending a big file to a client ought to be easy. With the usual services it isn't:

* **Limited space.** Free plans fill up quickly, and bigger plans are a monthly bill.
* **Slow.** Your file travels to a data centre, often in another country, and your client then downloads it back from there.
* **Extra steps.** With sync-style services you copy the file into a folder, wait for the background sync to finish, and then your client waits to download it, and sometimes copies it again out of their own synced folder.
* **You never find out when they have it.** Clients rarely tell you they have finished downloading, and even fewer remember to say "you can delete that now". So your file sits there, using up your space, for ever.
* **Sign-ups and passwords.** Many services want your client to create an account or make sense of sharing options, which is a lot to ask of someone who just needs a file.

Burnbox does one simple thing instead: **a link, optionally with a password, that expires and deletes the file by itself.** Choose how long it lives (from an hour to eight weeks) or "one time download", where the file is removed as soon as it has been downloaded. The person you send it to just clicks the link. There is nothing for them to sign up for and nothing for you to chase or tidy up.

It is made for people who send large files regularly: photographers delivering galleries, video makers sending masters, and anyone else whose files are too big for e-mail and too much hassle for the alternatives.

### Why hosting it yourself is better

* **Fast on your own network.** Upload over your LAN and the file is on the server when the upload finishes. There is no copying into a folder and no waiting for a background sync. On a 2.5 Gb or 25 Gb network that is far quicker than pushing the same file across the internet, even over a fast line.
* **Fast for your client too.** Hosted services are often in another country. Your server sits on your own internet connection, usually in the same country as your client. As an example, a 1 Gb fibre line that uploads at around 500 Mb/s gives your client a much faster download than most hosted services will.
* **No size limit except your disk.** Burnbox sets no limit of its own unless you ask for one (`maxFileSize`), so a file of hundreds of gigabytes, or a terabyte, is fine if you have the space.
* **Resumable.** If the connection drops mid-upload, the upload carries on from where it stopped rather than starting again. Downloads can be resumed too.
* **You can tell when it is done.** The admin page shows when each upload was last downloaded, one-time links delete themselves after the first download, and an optional webhook can notify another system.
* **Your files stay on your server.** Nothing is handed to a third party.

### What you take on

It is your server, so it is only as available as the machine it runs on. You need somewhere for it to run, enough disk space, and a way for clients to reach it from the internet (a domain name and either a port forward or a tunnel). Your internet upload speed still limits how fast clients can download. Backups, if you want them, are up to you. Files are stored as they are on the server's disk, so use disk encryption if you need it.

### Keep your uploads private

Out of the box, anyone who finds your Burnbox can upload files to it, so run it behind a reverse proxy such as nginx (which also gives you HTTPS) and put a password on uploading. There are two easy ways, and you can use either or both:

* **A login on the upload page only.** Download links stay open, so your clients need no password, but nobody can upload without logging in. It is a simple switch: one line in the nginx config turns it on or off. A tested example is in [`docs/nginx-ssl-example.conf`](docs/nginx-ssl-example.conf), and [Running it behind nginx](#running-it-behind-nginx) explains it.
* **Burnbox's own upload password.** Set `BURNBOX_UPLOAD_PASS` and Burnbox asks for it before accepting uploads.

The `/admin` page has its own password (`BURNBOX_ADMIN_PASS`).

These are shared passwords, not individual user accounts. A better sign-in is planned for later; see [issue #30](https://github.com/marshalleq/burnbox/issues/30).

## Features

* No accounts or sign-up for the people you send to
* Resumable uploads ([tus.io](https://tus.io)) and resumable downloads (HTTP range requests): big files and flaky connections
* Expiry from an hour to eight weeks, or one-time download; the choices are configurable
* Optional download password for each upload (stored as an Argon2 hash)
* ZIP archive download for whole uploads (offered when there is more than one file)
* Direct per-file download button
* In-browser preview of images and text files
* Optional webhooks when a file is uploaded or downloaded
* `/admin` page listing every upload (gated by `BURNBOX_ADMIN_PASS`)
* 16 languages, and a mobile-friendly web interface
* Runs on Node 26 or from a multi-architecture Docker image

## Quickstart

### Docker

A multi-architecture image (amd64 and arm64) is published to `ghcr.io/marshalleq/burnbox`: `latest` follows `master`, and release tags follow `v*` tags. To build it yourself instead:

```bash
git clone https://github.com/marshalleq/burnbox.git
cd burnbox
docker build -t burnbox .
# Generate a real admin password and keep it somewhere safe. Burnbox refuses to
# start if a password is empty or a placeholder such as "secret" or "admin".
export BURNBOX_ADMIN_PASS="$(openssl rand -base64 24)"
docker run -d --name burnbox -p 3000:3000 \
  -e BURNBOX_ADMIN_PASS \
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

## Running it behind nginx

Run Burnbox on the same machine as nginx, so that only nginx can reach it, and let nginx handle HTTPS. The complete, tested example is [`docs/nginx-ssl-example.conf`](docs/nginx-ssl-example.conf). To use it:

1. Start Burnbox with these settings (see [Configuration](#configuration) for what each does):
   * `BURNBOX_TRUST_PROXY=1`, so Burnbox sees each visitor's real address. Without it every visitor looks like nginx.
   * `BURNBOX_UPLOAD_APP_PATH=/up/`, which moves the upload page to `/up/` so nginx can put a login on it while download links stay open.
   * With Docker, publish the port to the local machine only (`-p 127.0.0.1:3000:3000`). Without Docker, also set `BURNBOX_IFACE=127.0.0.1`.
2. Create a login for uploading: `sudo sh -c 'echo "alice:$(openssl passwd -apr1)" >> /etc/nginx/burnbox.htpasswd'`
3. Copy the example into nginx, change the server name and certificate paths, and reload nginx.

**Turning the upload login on or off** is one line in the `location /up/` block of the example: `auth_basic "Burnbox uploads";` is on, and `auth_basic off;` is off. Reload nginx after changing it (`sudo nginx -s reload`). With the login off, anyone who can reach `/up/` can upload, so only do that on a private network or when you use `BURNBOX_UPLOAD_PASS` instead.

The example also sets `client_max_body_size 0`. nginx refuses anything over 1 MB by default and Burnbox uploads in 5 MB pieces, so without that line big uploads fail with "413 Request Entity Too Large".

What the example gives you, all checked by running it: `/up/` and the upload endpoint refuse anyone without a login; download pages, files, ZIPs and range requests work without a login; a 60 MB file uploaded in pieces, interrupted and resumed arrived byte-for-byte identical; and with the login switched off, `/up/` and uploads open up without one.

## Configuration

Every setting has a default, so Burnbox runs with none of them set. Change settings in either of two ways. If both set the same thing, the environment variable wins.

1. **Environment variables.** Each setting has one, named `BURNBOX_` plus the setting in capitals with underscores (`adminPass` is `BURNBOX_ADMIN_PASS`). This is the usual way with Docker: `-e BURNBOX_PORT=8080`.
2. **A config file.** Put a `config.production.js` (or `config.<NODE_ENV>.js`) next to `config.js`, exporting the settings you want to change. See `config.dev.js` for an example. Do not edit `config.js` itself.

How an environment variable is read depends on the setting:

* **Numbers and sizes** must be whole numbers. Sizes are in bytes (`BURNBOX_MAX_FILE_SIZE=2147483648` is 2 GiB, and `2GB` is rejected).
* **On/off settings** take `true` or `false`.
* **Lists** (`plugins`) are separated by commas.
* **`retentions`** is JSON.
* **Settings that can be off** (passwords, the HTTPS files, `corsOrigin`, `accessLog`, `forceHttps`, `trustProxy`, the webhooks and `mailTemplate`) are switched off with the word `false`. `port` and `sslPort` can too, and `maxFileSize` and `maxBucketSize` mean "no limit" when set to `false`.
* **A value that does not fit stops Burnbox at start-up** with a message naming the variable, rather than being guessed at.

### Where and how Burnbox listens

| Setting | Environment variable | Default | What it does |
|---|---|---|---|
| `uploadDir` | `BURNBOX_UPLOAD_DIR` | `./data` (the Docker image uses `/data`) | Folder where uploaded files and their details are kept. The user running Burnbox must be able to write to it. |
| `iface` | `BURNBOX_IFACE` | `0.0.0.0` | Network address to listen on. `0.0.0.0` means every interface. Use `127.0.0.1` when a reverse proxy on the same machine is in front. |
| `port` | `BURNBOX_PORT` | `3000` | Port for plain HTTP. `false` (or `0`) switches HTTP off. |
| `sslPort` | `BURNBOX_SSL_PORT` | `8443` | Port for built-in HTTPS. It only starts when `sslPort`, `sslKeyFile` and `sslCertFile` are all set. |
| `sslKeyFile` | `BURNBOX_SSL_KEY_FILE` | off | Path to the private key for built-in HTTPS. |
| `sslCertFile` | `BURNBOX_SSL_CERT_FILE` | off | Path to the certificate for built-in HTTPS. A reverse proxy such as nginx (see `docs/nginx-ssl-example.conf`) is the recommended way to do HTTPS. |
| `forceHttps` | `BURNBOX_FORCE_HTTPS` | off | Redirects plain HTTP requests to HTTPS. `true` redirects to HTTPS on the same host; a full address such as `https://example.com:8443` redirects there. If you set this without `trustProxy`, Burnbox trusts every proxy header and logs a warning, so set `trustProxy` as well. |
| `trustProxy` | `BURNBOX_TRUST_PROXY` | off | Set this whenever a reverse proxy is in front of Burnbox. Use the number of proxies (`1` for one) or an address such as `loopback`. Without it every visitor looks like the proxy, so access logs show the proxy's address and the limits below count everyone together. Do not use `true`: it trusts forged headers. |
| `baseUrl` | `BURNBOX_BASE_URL` | `/` | Path to serve Burnbox from, for example `/transfer/` when it shares a domain with other sites. A trailing slash is added if missing. |
| `uploadAppPath` | `BURNBOX_UPLOAD_APP_PATH` | `/` | Moves the upload page and the upload endpoint to a path under `baseUrl`, for example `/up/`. Downloads stay where they are, and visiting the site root redirects to the upload page. This lets you expose download links publicly while restricting `/up/` in your reverse proxy. |

### Passwords and protection

Passwords that are set but empty, or obvious placeholders (`secret`, `password`, `admin`, `changeme`, `test` and similar), stop Burnbox from starting, so a copied example cannot go live by accident. Leave a password unset to switch that feature off. `NODE_ENV=dev` is exempt, for local development.

| Setting | Environment variable | Default | What it does |
|---|---|---|---|
| `adminPass` | `BURNBOX_ADMIN_PASS` | off | Turns on the `/admin` page, which lists every upload (created, last downloaded, expiry and size) behind this password. |
| `uploadPass` | `BURNBOX_UPLOAD_PASS` | off | Requires this password to upload. Downloads are not affected. Recommended whenever Burnbox is reachable from the internet. |
| `requireBucketPassword` | `BURNBOX_REQUIRE_BUCKET_PASSWORD` | `false` | When `true`, every upload must set a download password. Enforced by the server, not only the upload page. |
| `authFailureLimit` | `BURNBOX_AUTH_FAILURE_LIMIT` | `20` | How many wrong passwords one visitor may try every 15 minutes (admin, upload and download passwords) before further requests are refused with a `429` response. Only wrong guesses count: correct passwords, and requests that send no password at all, do not. |
| `downloadRateLimit` | `BURNBOX_DOWNLOAD_RATE_LIMIT` | `600` | File and ZIP downloads one visitor may start per minute. |
| `corsOrigin` | `BURNBOX_CORS_ORIGIN` | off | Burnbox's own pages need no cross-origin access, so it is off. To let another website upload to this instance, set a comma-separated list of the exact origins (for example `https://files.example.com`). Allowing every origin (`*`) is deliberately not possible and stops Burnbox from starting. |

Download passwords are stored as Argon2 hashes.

### Uploads and expiry

| Setting | Environment variable | Default | What it does |
|---|---|---|---|
| `retentions` | `BURNBOX_RETENTIONS` | one time, 1 hour, 6 hours, 1 day, 3 days, 1 week, 2 weeks, 4 weeks, 8 weeks | The expiry choices offered to uploaders, as JSON. Each key is a number of seconds, or `one-time` (deleted after it is downloaded once), and each value is the label shown. Example: `{"one-time":"once","3600":"1 hour","86400":"1 day"}`. Labels are translated when a language file has them. |
| `defaultRetention` | `BURNBOX_DEFAULT_RETENTION` | `604800` (1 week) | Which choice is pre-selected. Must be one of the keys in `retentions`, otherwise Burnbox will not start. |
| `maxAge` | `BURNBOX_MAX_AGE` | `6480000` seconds (75 days) | Hard limit: every file is deleted this long after upload, whatever its retention. It is what removes one-time files that nobody downloaded. |
| `maxFileSize` | `BURNBOX_MAX_FILE_SIZE` | no limit | Largest single file, in bytes. Checked in the browser and again by the server. |
| `maxBucketSize` | `BURNBOX_MAX_BUCKET_SIZE` | no limit | Largest total size, in bytes, of all the files in one upload (one share link). Checked in the browser and again by the server. |

### Appearance and sharing

| Setting | Environment variable | Default | What it does |
|---|---|---|---|
| `defaultLanguage` | `BURNBOX_DEFAULT_LANGUAGE` | `en` | Language used when the visitor's browser asks for one Burnbox does not have. Available: `de`, `el`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `nl`, `pl`, `pt`, `ru`, `sv`, `tr`, `zh`, `zh-tw`. Otherwise the browser's own language is used. |
| `disableQrCode` | `BURNBOX_DISABLE_QR_CODE` | `false` | `true` hides the QR-code button on the upload-complete screen. |
| `mailTemplate` | `BURNBOX_MAIL_TEMPLATE` | `mailto:?subject=File Transfer&body=You can download the files here: %%URL%%` | The e-mail link on the upload-complete screen. `%%URL%%` is replaced with the download link. `false` hides the link. |
| `maxPreviewSize` | `BURNBOX_MAX_PREVIEW_SIZE` | `2097152` (2 MiB) | Largest file, in bytes, that gets a preview button on the download page. |

### Logging and integrations

| Setting | Environment variable | Default | What it does |
|---|---|---|---|
| `accessLog` | `BURNBOX_ACCESS_LOG` | `:date[iso] :method :url :status :response-time :remote-addr` | Format of the line written for each request, using [morgan](https://github.com/expressjs/morgan#tokens) tokens. `false` switches the access log off. |
| `plugins` | `BURNBOX_PLUGINS` | `file-downloaded-webhook,file-uploaded-webhook` | Which plugins from the `plugins/` folder are loaded. Remove a name to turn that plugin off. |
| `fileUploadedWebhook` | `BURNBOX_FILE_UPLOADED_WEBHOOK` | off | Address that receives a `POST` each time a file finishes uploading. |
| `fileDownloadedWebhook` | `BURNBOX_FILE_DOWNLOADED_WEBHOOK` | off | Address that receives a `POST` each time someone starts a download. The data sent is described in `docs/configuration.md`. Passwords are never sent. |

### Other environment variables

| Variable | What it does |
|---|---|
| `NODE_ENV` | Chooses the config file (`config.<NODE_ENV>.js`). `npm start` and the Docker image use `production`. `dev` is for local development: it also allows a simple password. |
| `DEBUG` | `DEBUG=burnbox:*` turns on detailed logging. |
| `BURNBOX_VERSION` | Read when the frontend is built: a version label made available to the page as `window.BURNBOX_VERSION`. Defaults to the git commit. |

## Customization

`public/pug/upload.pug` and `download.pug` are the entry templates. Add your logo/styles there.

## Limitations

* Files are stored unencrypted on the server's disk, and there is no end-to-end encryption in the browser (yet)
* `Download all as ZIP` does not support resuming the download

## Development, checks and automatic updates

The repository looks after its own dependencies and only asks for a human when a decision is needed.

**Checks.** Every push and pull request runs one job, `ci` (in `.github/workflows/ci.yml`), before anything else:

1. Lints the workflow files (`actionlint`).
2. Installs the server and frontend dependencies from their lockfiles.
3. Syntax-checks every server file.
4. Checks that this README documents every setting in `config.js`.
5. Builds the frontend.
6. Smoke-tests the server (`.github/scripts/smoke-test.sh`): starts it, loads each page, uploads and downloads files over tus, checks a two-file ZIP, the password rules, the wrong-password limit, CORS, and that environment variables are read correctly and bad ones are refused.

The Docker image is only built and pushed if `ci` passes. `master` is protected: the `ci / ci` check must pass before a change merges, and force-pushes and deletion are blocked. Repository admins are not forced to follow the check, so a broken `master` can still be repaired directly.

A separate check (`.github/workflows/nginx-example.yml`, not required) runs Burnbox behind the example nginx config and verifies the claims in [Running it behind nginx](#running-it-behind-nginx). It runs when the example or the server changes, and weekly.

To run the same checks locally, use the Node version in `.nvmrc`, then: `npm ci && (cd app && npm ci && npm run build) && .github/scripts/smoke-test.sh`.

**Automatic updates.** Dependabot (`.github/dependabot.yml`) checks both npm folders (`/` and `/app`), the Dockerfile and the GitHub Actions each week, and raises security fixes as soon as an advisory is published.

* Minor and patch updates are grouped into one pull request per area. They are merged automatically once `ci` passes (`.github/workflows/dependabot-automerge.yml`).
* Major updates are never merged automatically. They stay open as pull requests until someone has tested and decided on them.
* The image is rebuilt from scratch every Sunday so that base-image security fixes are picked up even when no code has changed.
* **Daily advisory watch** (`.github/workflows/advisory-watch.yml`). Dependabot only knows GitHub's reviewed advisory list, so each day this also checks advisories that the upstream libraries publish in their own repositories, Node.js core vulnerabilities against the Node version in the published image, and any dependency licence that is not on the allow-list. If something applies it opens (and keeps up to date) one issue titled "Advisory watch: findings that apply to Burnbox", and closes it when nothing applies. If a check cannot run, the job fails rather than reporting all clear.
* **CodeQL** (`.github/workflows/codeql.yml`) scans Burnbox's own JavaScript and Vue code for security bugs on every push and pull request, and weekly. Results appear under Security, then Code scanning.

**Pinned or overridden dependencies.** None at the moment. If one is ever needed to clear a security advisory in build-time tooling, it is recorded here with the reason and removed once the upstream packages catch up.

**Browser support.** The frontend uses Vue 3, which does not support Internet Explorer 11.

## Third-party notices

* Icons are [Font Awesome Free](https://fontawesome.com/license/free) (icons: CC BY 4.0, code: MIT).
* The stylesheet is a customised build of [Bootstrap](https://getbootstrap.com) 3.3.7 (MIT). Only the CSS is used.

## License

[BSD-2-Clause](LICENSE)
