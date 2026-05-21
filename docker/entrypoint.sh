#!/bin/sh
set -e

echo "Starting AIO CrossBackup Container (Role: $ROLE)..."

# 1. SSH CONFIGURATION & RESTRICTIONS
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ "$ROLE" = "client" ] && [ -n "$SSH_PRIVATE_KEY" ]; then
    echo "Injecting Client SSH Private Key..."
    echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_ed25519
    chmod 600 /root/.ssh/id_ed25519
fi

if [ "$ROLE" = "target" ] && [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "Setting up Target Authorized Keys with strict Borg restrictions..."
    # The ultimate lockdown: Force only borg serve, disable all other SSH features
    echo "command=\"borg serve --restrict-to-path /backups\",restrict $SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
fi

# 2. WIREGUARD CONFIGURATION
WG_CONF="/etc/wireguard/wg0.conf"
if [ "$ENABLE_WIREGUARD" = "true" ]; then
    if [ ! -f "$WG_CONF" ]; then
        echo "Generating wg0.conf template..."
        # Zero-Trust Firewall built right into the WG config
        IPTABLES_UP="iptables -I INPUT 1 -i wg0 -j DROP; iptables -I OUTPUT 1 -o wg0 -j DROP; iptables -I INPUT 1 -i wg0 -p tcp --dport 22 -j ACCEPT; iptables -I OUTPUT 1 -o wg0 -p tcp --sport 22 -j ACCEPT; iptables -I OUTPUT 1 -o wg0 -p tcp --dport 22 -j ACCEPT; iptables -I INPUT 1 -i wg0 -p tcp --sport 22 -j ACCEPT"
        IPTABLES_DOWN="iptables -D INPUT -i wg0 -j DROP; iptables -D OUTPUT -o wg0 -j DROP; iptables -D INPUT -i wg0 -p tcp --dport 22 -j ACCEPT; iptables -D OUTPUT -o wg0 -p tcp --sport 22 -j ACCEPT; iptables -D OUTPUT -o wg0 -p tcp --dport 22 -j ACCEPT; iptables -D INPUT -i wg0 -p tcp --sport 22 -j ACCEPT"

        if [ "$WG_MODE" = "server" ]; then
            IP="10.10.10.1/24" # Server gets .1
            cat <<EOF > "$WG_CONF"
[Interface]
Address = $IP
ListenPort = 51821
PrivateKey = $WG_PRIVATE_KEY
PostUp = $IPTABLES_UP
PreDown = $IPTABLES_DOWN

[Peer]
PublicKey = $WG_PEER_PUBLIC_KEY
AllowedIPs = 10.10.10.2/32
EOF
        else
            IP="10.10.10.2/24" # Client gets .2
            cat <<EOF > "$WG_CONF"
[Interface]
Address = $IP
PrivateKey = $WG_PRIVATE_KEY
PostUp = $IPTABLES_UP
PreDown = $IPTABLES_DOWN

[Peer]
PublicKey = $WG_PEER_PUBLIC_KEY
AllowedIPs = 10.10.10.1/32
Endpoint = $WG_ENDPOINT
PersistentKeepalive = 25
EOF
        fi
        echo "WireGuard config generated."
    fi
    wg-quick up wg0
fi

# 3. BORGMATIC CONFIG TEMPLATE (Client Only)
if [ "$ROLE" = "client" ] && [ ! -f /etc/borgmatic.d/config.yaml ]; then
    echo "Generating default borgmatic.yaml template..."

    # Generate a random 32-character passphrase if the file doesn't exist
    if [ ! -f /etc/borgmatic.d/passphrase ]; then
        echo "Generating secure random passphrase..."
        tr -dc A-Za-z0-9_ < /dev/urandom | head -c 32 > /etc/borgmatic.d/passphrase
    fi

    TARGET_IP=$([ "$ENABLE_WIREGUARD" = "true" ] && echo "10.10.10.2" || echo "TARGET_IP_OR_DOMAIN")
    TARGET_PORT=$([ "$ENABLE_WIREGUARD" = "true" ] && echo "22" || echo "2222")
    CLIENT_PUSH=${KUMA_CLIENT_PUSH_URL:-"https://kuma.yourdomain.com/api/push/CLIENT_ID"}

    cat "CHANGEME" > /etc/borgmatic.d/passphrase
    
    cat <<EOF > /etc/borgmatic.d/config.yaml
location:
    source_directories:
        - /source_data
    repositories:
        - ssh://root@${TARGET_IP}:${TARGET_PORT}/backups/my_repo.borg
storage:
    encryption_passcommand: "cat /etc/borgmatic.d/passphrase"
retention:
    keep_daily: 7
    keep_weekly: 4
consistency:
    checks:
        - repository
        - archives
    check_last: 3
uptime_kuma:
    push_url: ${CLIENT_PUSH}
    states:
        - start
        - finish
        - fail
    verify_tls: true
EOF
    echo "ACTION REQUIRED: Initialize the repo by running:"
    echo "docker exec -it <container_name> borgmatic init -e repokey"
    echo "CRITICAL: Back up the contents of /etc/borgmatic.d/passphrase to a password manager!"
fi

# 4. START SERVICES
if [ "$ROLE" = "target" ]; then
    echo "Starting SSH target..."
    /usr/sbin/sshd
    
    if [ -n "$KUMA_TARGET_PUSH_URL" ]; then
        echo "Configuring 48-hour active freshness monitoring..."
        cat << 'EOF' > /usr/local/bin/verify-freshness.sh
#!/bin/sh
# This checks file modification timestamps, which works on encrypted files.
if [ "$(find /backups -type f -mtime -2 | wc -l)" -gt 0 ]; then
    curl -s "${KUMA_TARGET_PUSH_URL}?status=up&msg=OK" > /dev/null
else
    curl -s "${KUMA_TARGET_PUSH_URL}?status=down&msg=STALE_DATA" > /dev/null
fi
EOF
        chmod +x /usr/local/bin/verify-freshness.sh
        echo "0 */12 * * * /usr/local/bin/verify-freshness.sh" >> /etc/crontabs/root
    fi
fi

if [ "$ROLE" = "client" ]; then
    > /etc/crontabs/root
    [ -n "$CRON_SCHEDULE" ] && echo "$CRON_SCHEDULE /usr/bin/borgmatic --syslog-verbosity 1" >> /etc/crontabs/root
    [ -n "$CRON_CHECK_SCHEDULE" ] && echo "$CRON_CHECK_SCHEDULE /usr/bin/borgmatic check --syslog-verbosity 1" >> /etc/crontabs/root
fi

crond -b
echo "Container initialized successfully."
exec tail -f /dev/null
