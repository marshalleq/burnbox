# Deployment as Systemd service 

You can also install Burnbox as (Linux) system service. Most distributions
use Systemd as main init system. You should **not** run Burnbox with root privileges!

**Preparation**

```bash
# Create a target folder for Burnbox
mkdir -p /opt/burnbox
cd /opt/burnbox

# Download and extract a prebuild
curl -sL https://github.com/marshalleq/burnbox/releases/download/1.1.0-beta/burnbox-1.1.0-beta.tar.gz | tar xz --strip 1

# Install dependencies
npm install --production

# Add a user burnbox
sudo useradd --system burnbox
 
# Make burnbox owner of /opt/burnbox
sudo chown -R burnbox:burnbox /opt/burnbox 
```

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
