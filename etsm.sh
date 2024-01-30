#!/bin/bash

TIMESTAMP_DAY=$( date +%Y/%m/%d )
TIMESTAMP=$( date +%H:%M )

cd meta

echo "git pull"
git pull

echo "git add"
git add --all --force

echo "git commit..."
git commit -m "updating nft meta ${TIMESTAMP_DAY} ${TIMESTAMP}" *

echo "git push..."
git push

find ./curl -maxdepth 1 -type f -exec echo "bash {}" \;