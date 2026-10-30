# Deployment using Docker

Using Docker is the most easy and recommended way to run Burnbox. There is a
multi-architecture (amd64 and arm64) image on the
[GitHub Container Registry](https://github.com/marshalleq/burnbox/pkgs/container/burnbox),
rebuilt whenever a change is merged and every Sunday to pick up base-image fixes.

```bash
docker run -d -v $PWD/data:/data -p 3000:3000 ghcr.io/marshalleq/burnbox
```

The data folder must be writable by UID 1000 (`sudo chown -R 1000 $PWD/data`).
The above command starts the Burnbox Docker container and 
 * `-d` puts the process into background (daemon mode)
 * `-v` mounts the data volume into the container
 * `-p` forwards the traffic from port 3000 into the container

**Protipp**: `latest` (and `master`) follow the `master` branch. Once releases are tagged
`v1.2.3`, matching `1.2.3` and `1.2` image tags will also appear.

If you want to customize some Burnbox configurations use environment parameters
by adding `-e` flags to the `docker run` command.

```bash
docker run -v $PWD/data:/data -p 3000:8080 \
  -e BURNBOX_PORT=8080 \
  -e BURNBOX_DEFAULT_RETENTION=3600 \
  ghcr.io/marshalleq/burnbox
```

**Protipp**: By adding `--restart always` Docker will autostart the container after reboots.  
