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
    cronie \
    cronie-anacron

# Configure SSH server
RUN mkdir -p /var/run/sshd /root/.ssh /etc/wireguard /etc/borgmatic.d && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME /etc/borgmatic.d
VOLUME /etc/wireguard
VOLUME /backups

ENTRYPOINT ["/entrypoint.sh"]
