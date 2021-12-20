#!/bin/bash

# add via `crontab -e`:
#
#   */5 * * * * /usr/bin/flock -w 0 $HOME/src/go-notify/.lock $HOME/src/go-notify/check.sh 2>&1 >> /var/log/build/go-notify.log

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd))

NOTIFY_TEAM=dev
NOTIFY_CHANNEL=town-square

HOST=$(jq -r '.["go-notify"].instanceUrl' $HOME/.config/mmctl)
TOKEN=$(jq -r '.["go-notify"].authToken' $HOME/.config/mmctl)

mmcurl() {
  local method=$1
  local url=$HOST/api/v4/$2
  if [ ! -z "$3" ]; then
    body="-d"
  fi
  curl \
    -s \
    -m 30 \
    -X $method \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    $body "$3" \
    $url
}

NOTIFY_TEAMID=$(mmcurl GET teams/name/$NOTIFY_TEAM|jq -r '.id')
NOTIFY_CHANNELID=$(mmcurl GET teams/$NOTIFY_TEAMID/channels/name/$NOTIFY_CHANNEL|jq -r '.id')

mmfile() {
  local url=$HOST/api/v4/files
  curl \
    -s \
    -H "Authorization: Bearer $TOKEN" \
    -F "channel_id=$NOTIFY_CHANNELID" \
    -F "files=@$1" \
    $url
}

mmpost() {
  local message="$1"
  shift
  local files=''
  while (( "$#" )); do
    files+="\"$1\", "
    shift
  done
  if [ ! -z "$files" ]; then
    files=$(echo -e ',\n  "file_ids": ['$(sed -e 's/, $//' <<< "$files")']')
  fi
  POST=$(cat << END
{
  "channel_id": "$NOTIFY_CHANNELID",
  "message": "$message"$files
}
END
)
  mmcurl POST posts "$POST"
}

if [[ -z "$NOTIFY_TEAMID" || -z "$NOTIFY_CHANNELID" ]]; then
  echo "ERROR: unable to determine NOTIFY_TEAMID or NOTIFY_CHANNELID, exiting ($(date))"
  exit 1
fi

DL=https://go.dev/dl/
PLATFORM=linux
ARCH=amd64

set -e

echo "------------------------------------------------------------"
echo "STARTING ($(date))"

LATEST=$(wget -qO- "$DL"|sed -E -n "/<a .+?>go1\.[0-9]+(\.[0-9]+)?\.linux-amd64\.tar\.gz</p"|head -1)
ARCHIVE=$(sed -E -e 's/.*<a .+?>(.+?)<\/a.*/\1/' <<< "$LATEST")
STABLE=$(sed -E -e 's/^go//' -e "s/\.linux-amd64\.tar\.gz$//" <<< "$ARCHIVE")
VERSION="go$STABLE"

mkdir -p $SRC/.cache

echo "VERSION: $VERSION"

if [[ "$VERSION" =~ ^go1\.[0-9]+(\.[0-9]+)?$ ]]; then
  if [[ ! -f $SRC/.cache/$VERSION.notify_done ]]; then
    MSG='# New Go version **'${VERSION#go}'**!\n[Get it here]('$DL')'
    echo "MESSAGE: '$MSG'"
    mmpost "$MSG"
    echo ""
    touch $SRC/.cache/$VERSION.notify_done
  else
    echo "SKIPPING NOTIFY"
  fi
else
  echo "ERROR: VERSION($VERSION) !~ 'go1.\d(.\d)?'"
fi

echo "DONE ($(date))"

popd &> /dev/null
