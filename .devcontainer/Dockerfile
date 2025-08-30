FROM docker:28.1.1-dind-alpine3.21

# Install basic development tools
RUN apk add --update git sudo ca-certificates htop gnupg jq curl go golangci-lint nano vim

# Create user with same name, UID and GID as host
ARG REMOTE_USER
ARG REMOTE_UID
ARG REMOTE_GID
RUN <<EOF
	OLDUSER=$(awk -F: '{if ( $3 == '${REMOTE_UID}' ) print $1}' /etc/passwd)
	deluser --remove-home ${OLDUSER}
	addgroup --gid ${REMOTE_GID} ${REMOTE_USER}
	adduser --disabled-password -u ${REMOTE_UID} --ingroup ${REMOTE_USER} ${REMOTE_USER}
	adduser ${REMOTE_USER} wheel
	adduser ${REMOTE_USER} docker
	echo '%wheel ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
EOF

ENV HOME=/home/${REMOTE_USER}

# Set permissions for shell history directories
RUN mkdir -p /shellhistory \
	&& chmod -R 700 /shellhistory \
	&& chown -R ${REMOTE_USER}:${REMOTE_USER} /shellhistory \
	&& ln -s /shellhistory/.ash_history /home/${REMOTE_USER}/.ash_history

USER ${REMOTE_USER}

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true
