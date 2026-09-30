containers=()
instances=()

latest_server_ver() {
  local subdist="${1:-${GEL_TEST_CHANNEL:-stable}}"
  local architecture
  architecture=$(uname -m)
  case "$architecture" in
    x86_64|amd64) architecture=amd64 ;;
    aarch64|arm64) architecture=arm64 ;;
    *) echo "Unsupported architecture: $architecture" >&2; return 1 ;;
  esac
  case "$subdist" in
    stable|testing) ;;
    *) echo "Unsupported channel: $subdist" >&2; return 1 ;;
  esac
  curl -fsSL "${GEL_REGISTRY_URL:-https://registry.gelstable.com}/apt/dists/${subdist}/main/binary-${architecture}/Packages" \
    | python3 "${BASH_SOURCE[0]%/*}/select-package.py" --arch "$architecture" \
        --slot "${GEL_TEST_SLOT:-}" --exact-version "${GEL_TEST_EXACT_VERSION:-}"
}

build_container() {
  if [[ "${GEL_TEST_IMAGE_READY:-}" = 1 ]]; then
    return
  fi
  local subdist="${1:-${GEL_TEST_CHANNEL:-stable}}"
  local idx_entry
  local -a buildargs
  idx_entry=$(latest_server_ver "$subdist") || return
  buildargs+=(--build-arg "version=$(jq -r .slot <<< "$idx_entry")"
              --build-arg "exact_version=$(jq -r .version <<< "$idx_entry")"
              --build-arg "subdist=$subdist")
  if [[ -n "${GEL_REGISTRY_URL:-}" ]]; then
    buildargs+=(--build-arg "registry_url=$GEL_REGISTRY_URL")
  fi
  if [[ -n "${GEL_KEY_FINGERPRINT:-}" ]]; then
    buildargs+=(--build-arg "key_fingerprint=$GEL_KEY_FINGERPRINT")
  fi
  docker build -t ghcr.io/gelstable/gel:latest "${buildargs[@]}" .
}


create_instance() {
  local port
  local -n _container="$1"
  local -n _instance="$2"

  local image
  local password
  local tls_ca_file
  local user

  local -a docker_args
  local -a image_args
  local -a connect_args
  local -a link_args

  image="$(echo "$3" | jq -r '.image // ""')"
  image="${image:-ghcr.io/gelstable/gel:latest}"
  user="$(echo "$3" | jq -r '.user // ""')"
  user="${user:-admin}"
  password="$(echo "$3" | jq -r '.password // ""')"
  database="$(echo "$3" | jq -r '.database // ""')"
  tls_ca_file="$(echo "$3" | jq -r '.tls_ca_file // ""')"
  extensions="$(echo "$3" | jq -r '.extensions // ""')"

  if [ $# -gt 2 ]; then
    shift 3
  else
    shift 2
  fi

  _container="edb_dock_$(uuidgen | sed s/-//g)"
  containers+=("$_container")
  _instance="testinst_$(uuidgen | sed s/-//g)"
  instances+=("$_instance")

  docker_args+=(
    --publish=5656
  )

  if [ -z "${tls_ca_file}" ]; then
    docker_args+=(
      --env=GEL_SERVER_TLS_CERT_MODE=generate_self_signed
    )
  fi

  if [ -z "${password}" ]; then
    docker_args+=(
      --env=GEL_SERVER_DEFAULT_AUTH_METHOD=Trust
    )
  fi
  if [ -n "${extensions}" ]; then
    docker_args+=(
      --env=GEL_DOCKER_EXTENSIONS="${extensions}"
    )
  fi

  while [ $# -gt 0 ]; do
    if [ "$1" == "--" ]; then
      shift
      break
    else
      docker_args+=( "$1" )
      shift
    fi
  done

  while [ $# -gt 0 ]; do
    image_args+=( "$1" )
    shift
  done

  docker run -d --name="${_container}" "${docker_args[@]}" \
    "$image" "${image_args[@]}"

  echo docker run -d --name="${_container}" "${docker_args[@]}" \
    "$image" "${image_args[@]}"

  port=$(docker inspect "${_container}" \
    | jq -r '.[0].NetworkSettings.Ports["5656/tcp"][0].HostPort')

  connect_args=(
    --port="${port}"
    --user="${user}"
    --wait-until-available=120s
  )

  link_args=(
    --non-interactive
  )

  if [ -n "${tls_ca_file}" ]; then
    connect_args+=(
      --tls-ca-file="${tls_ca_file}"
    )
  else
    link_args+=(
      --trust-tls-cert
    )
  fi

  if [ -n "${database}" ]; then
    connect_args+=(
      --database="${database}"
    )
  fi

  if [ -n "${password}" ]; then
    connect_args+=(
      --password-from-stdin
    )
  fi

  if [ -n "${password}" ]; then
    echo "${password}" \
      | gel "${connect_args[@]}" \
          instance link "${link_args[@]}" "${_instance}"
  else
    gel "${connect_args[@]}" \
      instance link "${link_args[@]}" "${_instance}"
  fi
}


common_teardown() {
  for cont in "${containers[@]}"; do
    echo "--- CONTAINER: $cont ---"
    docker logs "$cont"
  done
  if [[ ${#containers[@]} -gt 0 ]]; then
    docker rm -f "${containers[@]}" || :
  fi
  for instance in "${instances[@]}"; do
    gel instance unlink -I "${instance}" || :
  done
}
