#!/bin/bash

set -e


PLATFORM=${PLATFORM:-github}

VERSION=${VERSION:-v1.30.4}


OWNER=${OWNER}
REPO=${REPO}

TOKEN=${TOKEN}


if [ "${PLATFORM}" = "github" ]
then

curl \
-H "Authorization: token ${TOKEN}" \
-X POST \
"https://api.github.com/repos/${OWNER}/${REPO}/releases" \
-d "
{
 \"tag_name\":\"${VERSION}\",
 \"name\":\"nginx ${VERSION}\",
 \"body\":\"nginx build release\"
}
"


elif [ "${PLATFORM}" = "gitee" ]
then

curl \
-H "Authorization: token ${TOKEN}" \
-X POST \
"https://gitee.com/api/v5/repos/${OWNER}/${REPO}/releases" \
-d "
{
 \"tag_name\":\"${VERSION}\",
 \"name\":\"nginx ${VERSION}\",
 \"body\":\"nginx build release\"
}
"


else

echo "unsupported platform"

exit 1

fi