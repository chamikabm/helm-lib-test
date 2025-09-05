FROM alpine:3.20
ARG HELM_VERSION=v3.14.2
# Add openssl for checksum verification + libc compatibility tools
RUN apk add --no-cache curl bash git tar gzip ca-certificates openssl \
 && update-ca-certificates \
 && curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
 && helm plugin install https://github.com/helm-unittest/helm-unittest \
 && mkdir -p /workspace
WORKDIR /workspace
COPY scripts/run-tests.sh /usr/local/bin/run-tests
RUN chmod +x /usr/local/bin/run-tests
ENTRYPOINT ["run-tests"]
CMD ["--skip-plugin-install"]
