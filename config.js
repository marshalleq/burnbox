const path = require('path');
const fs = require('fs');
const fsp = require('fs-promise');

// Default Config
// Do not edit this, generate a config.<ENV>.js for your NODE_ENV
// or use ENV-VARS like BURNBOX_PORT=8000
const config = {
  "uploadDir": path.resolve(__dirname + '/data'),
  // set to serve Burnbox from a sub-path
  "baseUrl": '/',
  // use to set custom upload url (subfolder to baseUrl)
  "uploadAppPath": '/',
  "iface": '0.0.0.0',
  // set to false to disable HTTP
  "port": 3000,
  // HTTPS, set all 3 values to enable
  "sslPort": 8443,
  "sslKeyFile": false,
  "sslCertFile": false,
  // Force redirect to https
  // can be true or a specific url like https://example.com:8443
  // keep empty to disable
  "forceHttps": '',
  // Use trust proxy to show real IP on logs when reverse proxy are used
  // see https://expressjs.com/en/guide/behind-proxies.html for options
  "trustProxy": '',
  // retention options in seconds:label
  "retentions": {
    "one-time": "one time download",
    "3600": "1 Hour",
    "21600": "6 Hours",
    "86400": "1 Day",
    "259200": "3 Days",
    "604800": "1 Week",
    "1209600": "2 Weeks",
    "2419200": "4 Weeks",
    "4838400": "8 Weeks"
  },
  // admin password, set to false to disable /admin page
  // to enable /admin page set your password like this:
  // "adminPass": "YourSecurePassword",
  "adminPass": false,
  // upload password, set to false to disable
  "uploadPass": false,
  // make the bucket-password field mandatory
  "requireBucketPassword": false,
  "defaultRetention": "604800",
  // expire every file after maxAge (eg never downloaded one-time files)
  "maxAge": 3600 * 24 * 75, // 75 days
  // maximum file-size for previews in byte
  "maxPreviewSize": Math.pow(2, 20) * 2, // 2MB
  "mailTemplate": 'mailto:?subject=File Transfer&body=You can download the files here: %%URL%%',
  // see https://github.com/expressjs/morgan
  // set to false to disable logging
  "accessLog": ':date[iso] :method :url :status :response-time :remote-addr',
  // event webhooks
  // invokes an HTTP POST to a url whenever a file is downloaded
  // for more info, see the webhooks section of docs/configuration.md
  "fileDownloadedWebhook": null,
  "fileUploadedWebhook": null,
  // Fallback language
  "defaultLanguage": "en",
  // Limit upload size
  "maxFileSize": null, // Math.pow(2, 30) * 2, // 2GB
  "maxBucketSize": null, // Math.pow(2, 30) * 2, // 10GB
  "plugins": ['file-downloaded-webhook', 'file-uploaded-webhook'],
  // Disable the QR code button for download url sharing, set to true to disable
  "disableQrCode": false,
  // Wrong passwords allowed per IP address every 15 minutes before requests are refused.
  // Behind a reverse proxy, also set trustProxy so each visitor is counted separately.
  "authFailureLimit": 20,
  // File and ZIP downloads allowed per IP address per minute.
  "downloadRateLimit": 600,
};

// Load NODE_ENV specific config
const envConfFile = path.resolve(__dirname, `config.${ process.env.NODE_ENV }.js`);
if (process.env.NODE_ENV && fsp.existsSync(envConfFile)) {
  Object.assign(config, require(envConfFile));
}

// Load config from ENV VARS: BURNBOX_<NAME>, where <NAME> is the setting in UPPER_SNAKE_CASE
// (adminPass -> BURNBOX_ADMIN_PASS). Environment variables are always text, so each setting
// is read according to its type. A value that does not fit stops Burnbox with a clear message
// instead of being guessed at.
const ENV_BOOLEANS = ['disableQrCode', 'requireBucketPassword'];
const ENV_NUMBERS = ['port', 'sslPort', 'maxAge', 'maxPreviewSize', 'authFailureLimit', 'downloadRateLimit'];
const ENV_SIZES = ['maxFileSize', 'maxBucketSize']; // bytes; false means no limit
const ENV_LISTS = ['plugins'];
const ENV_JSON = ['retentions'];
// Text settings that can be switched off by setting them to the word "false".
const ENV_OFFABLE = [
  'adminPass', 'uploadPass', 'sslKeyFile', 'sslCertFile', 'accessLog',
  'forceHttps', 'trustProxy', 'fileDownloadedWebhook', 'fileUploadedWebhook', 'mailTemplate'
];

function readEnv(k, raw, envName) {
  const fail = (expected) => {
    throw new Error(`Refusing to start: ${ envName } must be ${ expected }, but it is "${ raw }".`);
  };
  const word = raw.trim().toLowerCase();
  if (ENV_BOOLEANS.includes(k)) {
    if (word === 'true') return true;
    if (word === 'false') return false;
    return fail('true or false');
  }
  if (ENV_NUMBERS.includes(k)) {
    if (word === 'false' && ['port', 'sslPort'].includes(k)) return false; // switch that listener off
    return /^\d+$/.test(word) ? parseInt(word, 10) : fail('a whole number' + (['port', 'sslPort'].includes(k) ? ' (or false to switch it off)' : ''));
  }
  if (ENV_SIZES.includes(k)) {
    if (word === 'false') return null;
    return /^\d+$/.test(word) ? parseInt(word, 10) : fail('a whole number of bytes (or false for no limit)');
  }
  if (ENV_LISTS.includes(k)) {
    return raw.split(',').map((item) => item.trim()).filter(Boolean);
  }
  if (ENV_JSON.includes(k)) {
    try {
      return JSON.parse(raw);
    } catch (e) {
      return fail('valid JSON');
    }
  }
  if (ENV_OFFABLE.includes(k) && word === 'false') return false;
  return raw;
}

for (const k in config) {
  const envName = 'BURNBOX_' + k.replace(/([A-Z])/g, $1 => "_" + $1).toUpperCase();
  if (process.env[envName]) {
    config[k] = readEnv(k, process.env[envName], envName);
  }
}

// Refuse to start with an empty or placeholder password. Unset (false) is fine: it
// switches the feature off. Local development (NODE_ENV=dev) may use a simple one.
const PLACEHOLDER_PASSWORDS = [
  'secret', 'password', 'changeme', 'change-me', 'admin', 'test',
  'yourpassword', 'yoursecurepassword'
];
if (process.env.NODE_ENV !== 'dev') {
  for (const k of ['adminPass', 'uploadPass']) {
    const v = config[k];
    if (v === false || v === null || v === undefined) continue;
    if (typeof v !== 'string' || v.trim() === '' || PLACEHOLDER_PASSWORDS.includes(v.trim().toLowerCase())) {
      const envName = 'BURNBOX_' + k.replace(/([A-Z])/g, $1 => '_' + $1).toUpperCase();
      throw new Error(`Refusing to start: ${ k } is empty or a placeholder. Set ${ envName } to a real secret.`);
    }
  }
}

// Burnbox sends no CORS headers: its own pages are same-origin. Anyone who set the old
// opt-in is told, rather than having it silently ignored.
if ('corsOrigin' in config || process.env.BURNBOX_CORS_ORIGIN) {
  throw new Error(
    'Refusing to start: the corsOrigin setting (BURNBOX_CORS_ORIGIN) has been removed. Burnbox sends no CORS ' +
    'headers. If another website must upload to it, add the headers in your reverse proxy instead.'
  );
}

for (const k of ['authFailureLimit', 'downloadRateLimit']) {
  if (!Number.isInteger(config[k]) || config[k] < 1) {
    throw new Error(`Refusing to start: ${ k } must be a whole number of at least 1, got ${ config[k] }.`);
  }
}

for (const key of Object.keys(config.retentions)) {
  if (key !== 'one-time' && !/^\d+$/.test(key)) {
    throw new Error(`Refusing to start: retentions key "${ key }" must be a number of seconds or "one-time".`);
  }
}
if (!Object.keys(config.retentions).includes(String(config.defaultRetention))) {
  throw new Error(
    `Refusing to start: defaultRetention "${ config.defaultRetention }" is not one of the retentions ` +
    `(${ Object.keys(config.retentions).join(', ') }).`
  );
}

if (!config.baseUrl.endsWith('/')) config.baseUrl = config.baseUrl + '/';
if (!config.uploadAppPath.endsWith('/')) config.uploadAppPath = config.uploadAppPath + '/';

config.uploadAppPath = config.baseUrl.substr(0, config.baseUrl.length - 1) + config.uploadAppPath;

// Load language files
config.languages = {
  [config.defaultLanguage]: require(`./lang/${ config.defaultLanguage }`) // default language
};
fs.readdirSync(path.resolve(__dirname, 'lang')).forEach(lang => {
  lang = lang.replace('.js', '');
  if (lang === config.defaultLanguage) return;
  config.languages[lang] = {
    ...config.languages[config.defaultLanguage],
    ...require(`./lang/${ lang }`)
  };
});

module.exports = config;
