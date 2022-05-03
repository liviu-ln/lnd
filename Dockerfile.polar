# If you change this value, please change it in the following files as well:
# /.travis.yml
# /dev.Dockerfile
# /make/builder.Dockerfile
# /.github/workflows/main.yml
# /.github/workflows/release.yml
FROM golang:1.17.3-alpine as builder

# Force Go to use the cgo based DNS resolver. This is required to ensure DNS
# queries required to connect to linked containers succeed.
ENV GODEBUG netdns=cgo

# Pass a tag, branch or a commit using build-arg.  This allows a docker
# image to be built from a specified Git state.  The default image
# will use the Git tip of master by default.
ARG checkout="master"
ARG git_url="https://github.com/lightningnetwork/lnd"

# Install dependencies and build the binaries.
RUN apk add --no-cache --update alpine-sdk \
    git \
    make \
    gcc \
&&  git clone $git_url /go/src/github.com/lightningnetwork/lnd \
&&  cd /go/src/github.com/lightningnetwork/lnd \
&&  git checkout $checkout \
&&  make

# Start a new, final image.
FROM golang:1.17.3-alpine as final

# Define a root volume for data persistence.
VOLUME /root/.lnd

# Add utilities for quality of life and SSL-related reasons. We also require
# curl and gpg for the signature verification script.
RUN apk add --no-cache --update alpine-sdk \
    git \
    make \
    gcc \
    bash \
    jq \
    ca-certificates \
    gnupg \
    curl \
    sudo \
    shadow \
    su-exec \
    vim

RUN go install github.com/go-delve/delve/cmd/dlv@latest

RUN echo 'root:root' | chpasswd

# Copy the binaries from the builder image.
COPY --from=builder /go/src/github.com/lightningnetwork/lnd/lncli-debug /bin/lncli
COPY --from=builder /go/src/github.com/lightningnetwork/lnd/lnd-debug /bin/lnd
COPY --from=builder /go/src/github.com/lightningnetwork/lnd/scripts/verify-install.sh /
COPY --from=builder /go/src/github.com/lightningnetwork/lnd/scripts/keys/* /keys/

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

# Store the SHA256 hash of the binaries that were just produced for later
# verification.
RUN sha256sum /bin/lnd /bin/lncli > /shasums.txt \
  && cat /shasums.txt

# Expose lnd ports (p2p, rpc).
VOLUME ["/home/lnd/.lnd"]

EXPOSE 9735 8080 10000

# Specify the start command and entrypoint as the lnd daemon.
ENTRYPOINT ["/entrypoint.sh"]

CMD ["lnd"]
