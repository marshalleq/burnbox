# Deployment as Systemd service 

You can also install Burnbox as (Linux) system service. Most distributions
use Systemd as main init system. You should **not** run Burnbox with root privileges!

**Preparation**

```bash
# Create a target folder for Burnbox
mkdir -p /opt/burnbox
cd /opt/burnbox

# Get the code (needs git and Node 26 or newer, check with: node -v)
git clone https://github.com/marshalleq/burnbox.git .

# Build the frontend, then install the server's runtime dependencies
(cd app && npm ci && npm run build)
npm ci --omit=dev

# Add a user burnbox
sudo useradd --system burnbox
 
# Make burnbox owner of /opt/burnbox
sudo chown -R burnbox:burnbox /opt/burnbox 
```

The sample unit file runs `/usr/bin/node`. If your distribution's Node is older than 26,
point `ExecStart` at the right binary. To set an admin or upload password, put
`BURNBOX_ADMIN_PASS=...` in a file readable only by root and reference it with
`EnvironmentFile=` in the unit. Burnbox refuses to start with a placeholder password.

**Systemd unit file**

Grab the [burnbox.service](https://github.com/marshalleq/burnbox/blob/master/docs/burnbox.service)
sample file, put it in `/etc/systemd/system/` and adjust to your needs.

```bash
cd /etc/systemd/system
sudo wget https://raw.githubusercontent.com/marshalleq/burnbox/master/docs/burnbox.service

# Start the service
sudo systemctl start burnbox

# Show the status
sudo systemctl status burnbox

# Enable autostart on boot
sudo systemctl enable burnbox
```
