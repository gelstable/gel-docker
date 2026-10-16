FROM debian:bookworm-slim
ARG version
ARG exact_version
ARG cli_version
ARG subdist=stable
ARG registry_url=https://registry.gelstable.com
ARG key_fingerprint=EBFC46CC958983DD73D6E7D7F7C050A836EDB7EC

ENV GOSU_VERSION=1.11
ENV DEFAULT_OS_USER=gel
ENV DEFAULT_SERVER_BINARY=gel-server-${version}
ENV VERSION=${version}

SHELL ["/bin/bash", "-c"]

RUN set -Eeo pipefail; shopt -s dotglob inherit_errexit nullglob; \
export DEBIAN_FRONTEND=noninteractive; \
(test -n "${version}" || \
  (echo ">>> ERROR: missing required 'version' build-arg" >&2 && exit 1)) \
&& ( \
    for i in $(seq 1 5); do [ $i -gt 1 ] && sleep 1; \
        apt-get update \
    && s=0 && break || s=$?; done; exit $s \
) \
&& ( \
    for i in $(seq 1 5); do [ $i -gt 1 ] && sleep 1; \
        apt-get install -y --no-install-recommends \
            apt-utils \
            gnupg \
            dirmngr \
            curl \
            wget ca-certificates \
            apt-transport-https \
            locales \
            procps \
            gosu \
            jq \
    && s=0 && break || s=$?; done; exit $s \
) \
&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8\
&& test -n "${cli_version}" \
&& test -n "${exact_version}" \
&& [[ "${exact_version}" =~ ^1:[0-9][0-9A-Za-z.+~]*-[0-9]+$ ]] \
&& [[ "${subdist}" = stable || "${subdist}" = testing ]] \
&& mkdir -p /etc/apt/keyrings \
&& curl --fail --silent --show-error --location \
    -o /etc/apt/keyrings/gelstable.asc "${registry_url}/keys/gelstable.asc" \
&& actual_fingerprint=$(gpg --batch --show-keys --with-colons /etc/apt/keyrings/gelstable.asc \
    | awk -F: '$1 == "pub" { primary=1; next } primary && $1 == "fpr" { print $10; primary=0 }') \
&& test "${actual_fingerprint}" = "${key_fingerprint}" \
&& printf 'Types: deb\nURIs: %s/apt\nSuites: %s\nComponents: main\nSigned-By: /etc/apt/keyrings/gelstable.asc\n' \
    "${registry_url}" "${subdist}" > /etc/apt/sources.list.d/gelstable.sources \
&& ( \
    for i in $(seq 1 5); do [ $i -gt 1 ] && sleep 1; \
        apt-get update \
    && s=0 && break || s=$?; done; exit $s \
) \
&& ( \
    server=gel-server-${version}=${exact_version}; \
    for i in $(seq 1 5); do [ $i -gt 1 ] && sleep 1; \
        env apt-get install -y "${server}" "gel-cli=${cli_version}" \
    && s=0 && break || s=$?; done; exit $s \
) \
&& package=gel-server \
&& ln -s /usr/bin/${package}-${version} /usr/bin/${package} \
&& apt-get remove -y gnupg dirmngr wget apt-transport-https \
&& apt-get purge -y --auto-remove \
&& rm -rf /var/lib/apt/lists/*

LABEL com.gelstable.server-version=${exact_version} com.gelstable.cli-version=${cli_version}

ENV LANG=en_US.utf8

EXPOSE 5656

VOLUME /var/lib/gel/data

COPY docker-entrypoint-funcs.sh docker-entrypoint.sh /usr/local/bin/
COPY show-secrets.sh /usr/local/bin/gel-show-secrets.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server"]
