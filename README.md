# OpenConnect Docker Container

Forked from https://github.com/aw1cks/openconnect to meet custom needs.

![github](https://github.com/jesusdf/openconnect/actions/workflows/main.yml/badge.svg)
![gitlab](https://gitlab.com/jesusdf/openconnect/badges/master/pipeline.svg)

## Why?

OpenConnect doesn't ship with any init scripts or systemd units.
It's also not easy to non-interactively provide username, password and especially OTP.
Additionally, running in a docker container gives some extra flexibility with routing.

Additionally, this fork allows split-tunneling, that is only routing traffic through the VPN 
for specific hostnames or subnets using [vpn-splice](https://github.com/dlenski/vpn-slice).

Also, you can specify the tun device name, in case you are using multiple VPNs on the same
machine.

## Where can I download it?

The image is built by GitHub Actions for amd64 & arm64 and pushed to the following repositories:

 - [Docker Hub](https://hub.docker.com/r/jesusdf/openconnect)

## How do I use it?

You can run the container using the specified arguments below.

### Basic container command

```shell
docker run -d \
--cap-add NET_ADMIN \
-e TUN_DEVICE=tun127 \
-e URL=https://my.vpn.com \
-e USER=myuser \
-e AUTH_GROUP=mygroup \
-e PASS=mypassword \
-e SPLICE_ARGS="server1.vpn.com 192.168.100.0/24" \
-e OTP=123456 \
-e SEARCH_DOMAINS="my.corporate-domain.com subdomain.my.corporate-domain.com" \
-e EXTRA_ARGS="--no-dtls" \
docker.io/jesusdf/openconnect'
```

### All container arguments

| Variable         | Explanation                                                                                                                                  | Example Value                                               |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------|
| `TUN_DEVICE`     | Name of the tun device to use                                                                                                                | `tun127`                                                    | 
| `URL`            | URL of AnyConnect VPN                                                                                                                        | `https://my.vpn.com`                                        |
| `USER`           | User to authenticate with                                                                                                                    | `myuser`                                                    |
| `AUTH_GROUP`     | Authentication Group to use when connecting to VPN (optional)                                                                                | `mygroup`                                                   |
| `PASS`           | Password to authenticate with                                                                                                                | `mypassword`                                                |
| `SPLICE_ARGS`    | Space separated list of hostnames or networks that should be routed through (or excluded of) the VPN                                         | `server1.vpn.com 192.168.100.0/24`                          |
| `OTP`            | OTP/2FA code (optional)                                                                                                                      | `123456`                                                    |
| `SEARCH_DOMAINS` | Search domains to use. DNS for these domains will be routed via the VPN's DNS servers (optional). Separate with a space for multiple domains | `my.corporate-domain.com subdomain.my.corporate-domain.com` |
| `EXTRA_ARGS`     | Any additional arguments to be passed to the OpenConnect client (optional). Only use this if you need something specific                     | `--verbose`                                                 |

Notice that `vpn-slice` accepts several different kinds of routes and hostnames on the command line (via SPLICE_ARGS environment variable):

- Hostnames *alone* (`hostname1`) as well as *host-to-IP* aliases (`alias2=alias2.bigcorp.com=192.168.1.43`).
  The former are first looked up using the VPN's DNS servers. Both are also added to the routing table, as
  well as to `/etc/hosts` (unless `--no-host-names` is specified). As in this example, multiple aliases can
  be specified for a single IP address.
- Subnets to *include* (`10.0.0.0/8`) in the VPN routes as well as subnets to explicitly *exclude* (`%10.123.0.0/24`).

There are many command-line options to alter the behavior of
`vpn-slice`; try `vpn-slice --help` to show them all.

### Requirements
 - `docker`
 - `sudo` (and permissions to run `ip` and `docker` as root)
 - `iproute2`
 - `jq`

## Building the container yourself

The following build args are used:

 - `BUILD_DATE` (RFC3339 timestamp)
 - `COMMIT_SHA` (commit hash from which image was built)

```shell
docker build \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo 'null')" \
  -t openconnect .
```

## Known issues

When running not in privileged mode, OpenConnect gives errors such as this:

`Cannot open "/proc/sys/net/ipv4/route/flush"`

This is normal and does not impact the operation of the VPN.

To suppress these errors, run with `--privileged`.

