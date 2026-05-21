# All-in-One CrossBackup
A zero-trust, containerized Borg backup solution.

This project provides a single, unified Docker image that operates as either a backup **Client** (initiator) or a **Target** (receiver). 
It handles automated backups using borgmatic and includes a built-in WireGuard VPN to seamlessly bypass NAT. 
Security is enforced through internal strict iptables firewalls and SSH command restrictions.


## Features
- **Unified image:** The exact same Docker image runs on both the source and destination servers, toggled via environment variables.
- **Built-in NAT traversal:** Integrated WireGuard VPN allows the backup client to securely push data even if both machines are behind NAT (requires the target to expose one UDP port).
- **Zero-Trust architecture:**
    - The Target machine uses strict SSH `authorized_keys` configuration to force the connection to *only* execute borg serve, locking it to the /backups directory.
    - When WireGuard is enabled, an internal iptables firewall automatically drops all traffic on the VPN interface except for SSH (port 22).

- **Automated configuration:** The container automatically generates the WireGuard tunnel configuration, iptables rules, and the initial borgmatic.yaml template upon first boot.
- **Dual-Layer monitoring:** Native integration with Uptime Kuma. The Client pushes active success/fail pings, while the Target runs a passive 48-hour "freshness" watchdog on the encrypted files.
- **Catch-up scheduling:** Uses cronie/anacron under the hood. If a machine is powered off during a scheduled backup, it will run immediately upon booting up.


## Architecture
You must deploy a pair of containers: one **Client** and one **Target**.

- **Client:** The machine whose data is being backed up. It runs the cron jobs, encrypts the data, and pushes it.
- **Target:** The machine storing the backups. It acts passively, receiving the data via SSH.

You can run this in two modes:
1. **WireGuard mode:** Used when the Client is behind NAT. The Target acts as a WireGuard server (exposing one UDP port). The Client establishes a secure tunnel, and pushes backups through the tunnel.
2. **SSH-only mode:** Used if the Target has a public IP address and you do not want to use a VPN. The Target exposes an SSH port directly to the internet.


## Prerequisites
Before deploying, generate your cryptographic keys on your local machine:

**1. Generate SSH keys (required for all modes)**

```bash
ssh-keygen -t ed25519 -f ./temp_key -N ""
```

Keep the private key for the Client, and the public key for the Target.

**2. Generate WireGuard keys (only if using WireGuard mode)**

```bash
# Generate keys for Machine A (Client)
wg genkey | tee client_privatekey | wg pubkey > client_publickey

# Generate keys for Machine B (Target)
wg genkey | tee target_privatekey | wg pubkey > target_publickey
```


## Quick start

### 1. Copy the templates to your servers
Decide if you are using WireGuard (`-wg`) or SSH-only (`-ssh`).   

Copy the corresponding folders from the `templates/` directory to your respective machines.
- **Client machine:** [templates/client-wg](./templates/client-wg) (or [client-ssh](./templates/client-ssh))
- **Target machine:** [templates/target-wg](./templates/target-wg) (or [target-ssh](./templates/target-ssh))

### 2. Generate your keys
Run this on a secure machine to generate the necessary keys for your `.env` files.

Generate SSH keys (required for all modes)
```bash
ssh-keygen -t ed25519 -f ./temp_key -N ""
cat temp_key.pub  # This is your SSH_PUBLIC_KEY
cat temp_key      # This is your SSH_PRIVATE_KEY
```

Generate WireGuard keys (only if using WireGuard mode)
```bash
# -- If you have a trusted WireGuard installation: 
wg genkey | tee client_privatekey | wg pubkey > client_publickey
wg genkey | tee target_privatekey | wg pubkey > target_publickey


# -- If you don't, you can run this temporary container to generate the keys:

# Run this for the Client keys:
docker run --rm ghcr.io/desktop31/aio-crossbackup:latest sh -c 'priv=$(wg genkey); pub=$(echo $priv | wg pubkey); echo -e "CLIENT_PRIVATE_KEY=$priv\nCLIENT_PUBLIC_KEY=$pub"'

# Run this for the Target keys:
docker run --rm ghcr.io/desktop31/aio-crossbackup:latest sh -c 'priv=$(wg genkey); pub=$(echo $priv | wg pubkey); echo -e "TARGET_PRIVATE_KEY=$priv\nTARGET_PUBLIC_KEY=$pub"'
```

### 3. Configure and start the Target
On your Target machine, navigate to the folder you copied in Step 1.

```bash
cp .env.example .env

# Open .env and populate your keys, ports, and URLs
vim .env

# Start the target container
docker compose up -d
```

### 4. Configure and start the Client
On your Client machine, navigate to the folder you copied in Step 1.

```bash
cp .env.example .env

# Open .env and populate your keys, target IP/endpoint, and URLs
vim .env

# Start the client container
docker compose up -d
```

### 5. Initialize the repository (Client only)
The **Client** container will automatically generate a template `config.yaml` inside your mapped `./config/borgmatic` directory.
This is where you can optionally customize the backup if you want to.

---
#### :warning: CRITICAL: Save or set encryption passphrase
The Client container automatically generates an encryption passphrase inside `./config/borgmatic/passphrase` to secure the backups.
You must **SAVE IT** or input your own before initializing the repository.

Without this passphrase, you **WON'T BE ABLE TO RECOVER YOUR BACKUPS**.

Initialize the Borg repository on the Target by executing this command on the Client machine:

```bash
docker exec -it aio-crossbackup_client-<wg/ssh> borgmatic init -e repokey
```

---
#### :warning: CRITICAL: Export your recovery key
Because `repokey` stores the actual encryption key inside the remote repository itself, your backups will be permanently lost if the remote repository's configuration file gets corrupted (even if you remember your passphrase).

Immediately after initialization, run this command to print your master key:

```bash
docker exec -it aio-crossbackup_client-<wg/ssh> borgmatic key export
```

Copy the output text and save it alongside your passphrase in a secure password manager.

---

Your automated backups will now run according to your `CRON_SCHEDULE`.


## Environment variable reference

### General options
- `ROLE`: Must be either "*client*" or "*target*".
- `ENABLE_WIREGUARD`: true or false.

### WireGuard options (requires ENABLE_WIREGUARD=true)
- `WG_MODE`: Must be server (usually the Target) or client (usually the Client).
- `WG_ENDPOINT`: Required for the client. The public IP/domain and port of the server (e.g., 198.51.100.1:51821).
- `WG_PRIVATE_KEY`: The WireGuard private key for this container.
- `WG_PEER_PUBLIC_KEY`: The WireGuard public key of the other container.

### Security options
- `SSH_PRIVATE_KEY`: (Client only). The full multi-line ed25519 private key.
- `SSH_PUBLIC_KEY`: (Target only). The ed25519 public key. The container automatically wraps this in severe restriction commands before applying it.

### Scheduling and monitoring
- `CRON_SCHEDULE`: (Client only). Standard cron syntax for the backup run (e.g., `0 3 * * *`).
- `CRON_CHECK_SCHEDULE`: (Client only). Standard cron syntax for repository consistency checks (e.g., `0 1 * * 0`).
- `KUMA_CLIENT_PUSH_URL`: (Client only). Pushed natively by Borgmatic on backup start, success, and failure.
- `KUMA_TARGET_PUSH_URL`: (Target only). Pushed every 12 hours. Reports "UP" if files in /backups were modified in the last 48 hours, and "DOWN" (Stale Data) if not.


## Security considerations
Even if the Client machine is fully compromised, the attacker cannot delete old backups or compromise the Target machine.

The entrypoint.sh automatically formats the Target's `authorized_keys` file to include `command="borg serve --restrict-to-path /backups",restrict`. 
This disables port forwarding, terminal access, and completely ignores whatever command the Client attempts to execute, forcing it exclusively into the Borg server protocol confined to the mapped storage directory.
