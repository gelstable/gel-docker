# Each Bats test runs in its own subshell; environment changes are intentional.
# shellcheck disable=SC2030,SC2031
load testbase

@test "select a full native server version from the Packages index" {
  local selected
  selected=$(latest_server_ver)
  local slot
  local version
  slot=$(jq -r .slot <<< "$selected")
  version=$(jq -r .version <<< "$selected")
  [[ "$slot" =~ ^[0-9]+$ ]]
  [[ "$version" =~ ^1:[0-9][0-9A-Za-z.+~]*-[0-9]+$ ]]
  export GEL_TEST_SLOT="$slot" GEL_TEST_EXACT_VERSION="$version"
  run latest_server_ver
  [[ "$status" = 0 ]]
  [[ "$(jq -r .version <<< "$output")" = "$version" ]]
}

@test "reject an exact server version absent from the Packages index" {
  export GEL_TEST_EXACT_VERSION=1:999999-1
  run latest_server_ver
  [[ "$status" != 0 ]]
}
