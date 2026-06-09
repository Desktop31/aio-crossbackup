FROM alpine:latest

RUN apk add --no-cache \
    borgbackup \
    borgmatic \
    wireguard-tools \
    iptables \
    iproute2 \
    openssh \
    tzdata \
    curl \
    fcron

# Configure SSH server
RUN mkdir -p /var/run/sshd /root/.ssh /etc/wireguard /etc/borgmatic.d && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# Mounts zfs snapshots 
COPY docker/generate_roots.sh /generate_roots.sh
RUN chmod +x /generate_roots.sh
# Unmounts zfs snapshots
COPY docker/cleanup_roots.sh /cleanup_roots.sh
RUN chmod +x /cleanup_roots.sh

VOLUME /etc/borgmatic.d
VOLUME /etc/wireguard
VOLUME /root
VOLUME /backups

ENTRYPOINT ["/entrypoint.sh"]
