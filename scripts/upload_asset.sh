#!/bin/sh

#
# Creates a release asset and pushes it to github
#

cd "$(dirname "$0")/../"
PROJECT_DIRECTORY=$(pwd)
echo "In project directory $PROJECT_DIRECTORY"

ORIGIN_URL=$(git config --get remote.origin.url)
GITHUB_ORG=$(echo "$ORIGIN_URL" | sed 's|.*:||;s|/.*$||')
GITHUB_REPO=$(echo "$ORIGIN_URL" | sed 's|.*/||;s|\.[^\.]*$||')
export GITHUB_ORG
export GITHUB_REPO

if [ -z "$GITHUB_TOKEN" ]; then
  printf "Error: Missing %s environment variable.\n" \
    GITHUB_TOKEN >&2
  exit 1
fi

git fetch origin 'refs/tags/*:refs/tags/*'
RAW_TAG="$(git describe --exact-match --tags 2> /dev/null || true)"
TAG=${RAW_TAG//v}
echo "Release tag found: $TAG"

if [ -z "$TAG" ]; then
  echo "Not a tagged commit. Skipping release.."
  exit
fi

# Check if this is a pre-release version (denoted by a hyphen):
if [ "${TAG#*-}" != "$TAG" ]; then
  PRE=true
else
  PRE=false
fi

RELEASE_TEMPLATE='{
  "tag_name": "%s",
  "name": "%s",
  "prerelease": %s,
  "draft": %s
}'

RELEASE_BODY="This is an automated release.\n\n"

create_release_draft() {
  # shellcheck disable=SC2034
  local ouput
  # shellcheck disable=SC2059
  if output=$(curl \
      --silent
      --request POST \
      --header "Authorization: token $GITHUB_TOKEN" \
      --header 'Content-Type: application/json' \
      --data "$(printf "$RELEASE_TEMPLATE" "$TAG" "$TAG" "$PRE" true)" \
      "https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/releases");
  then
    RELEASE_ID=$(echo "$output" | jq -re '.id')
    UPLOAD_URL_TEMPLATE=$(echo "$output" | jq -re '.upload_url')
  fi
}

upload_release_asset() {
  # shellcheck disable=SC2059
  curl \
    --silent
    --request POST \
    --header "Authorization: token $GITHUB_TOKEN" \
    --header 'Content-Type: application/zip' \
    --data-binary "@$1" \
    "${UPLOAD_URL_TEMPLATE%\{*}?name=$1&label=$2" \
    > /dev/null
}

update_release_body() {
  # shellcheck disable=SC2059
  curl \
    --silent
    --request PATCH \
    --header "Authorization: token $GITHUB_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "{\"body\":\"$RELEASE_BODY\"}" \
    "https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/releases/$1" \
    > /dev/null
}

publish_release() {
  # shellcheck disable=SC2059
  curl \
    --slient
    --request PATCH \
    --header "Authorization: token $GITHUB_TOKEN" \
    --header 'Content-Type: application/json' \
    --data "{\"draft\":false, \"tag_name\": \"$TAG\"}" \
    "https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/releases/$1" \
    > /dev/null
}

echo "Creating release draft $TAG"
create_release_draft

FILE="$PROJECT_DIRECTORY/lighthouse-lambda-$TAG.tgz"
echo "Uploading $FILE to $GITHUB_REPO"
upload_release_asset "$FILE" "lighthouse-lambda-$TAG.tgz"

echo "Updating release body"
update_release_body "$RELEASE_ID"

echo "Publishing release"
publish_release "$RELEASE_ID"