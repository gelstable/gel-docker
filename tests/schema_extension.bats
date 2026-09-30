load testbase

setup() {
  build_container
  docker build -t gel-test:schema-extension tests/schema_with_extension
}

teardown() {
  common_teardown
}

@test "install an extension" {
  local container_id
  local instance
  local before
  local slot
  slot=$(docker run --rm ghcr.io/gelstable/gel:latest printenv VERSION)
  before=$(docker run --rm ghcr.io/gelstable/gel:latest dpkg-query -W -f='${Version}' gel-server-"${slot}")

  create_instance container_id instance '{"image":"gel-test:schema-extension","extensions":"postgis"}'

  # wait until migrations are complete
  sleep 3

  # Complex objects like PostGisGeometry cannot be printed tab-separated
  gel -I "${instance}" query \
    "select ext::postgis::makepoint(1.0, 2.0)"
  run gel -I "${instance}" query --output-format=tab-separated \
    "select ext::postgis::x(ext::postgis::makepoint(1.0, 2.0))"
  [[ "$status" = 0 && "$output" = 1 ]]
  local after
  after=$(docker exec "$container_id" dpkg-query -W -f='${Version}' gel-server-"${slot}")
  [[ "$before" = "$after" ]]
}
