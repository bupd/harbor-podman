#!/bin/bash

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
source $DIR/common.sh

set +o noglob

usage=$'Please set hostname and other necessary attributes in harbor.yml first. DO NOT use localhost or 127.0.0.1 for hostname, because Harbor needs to be accessed by external clients.
Please set --with-trivy if needs enable Trivy in Harbor.
Please do NOT set --with-chartmuseum, as chartmusuem has been deprecated and removed.
Please do NOT set --with-notary, as notary has been deprecated and removed.'
item=0

# clair is deprecated
with_clair=$false
# trivy is not enabled by default
with_trivy=$false

# flag to using docker compose v1 or v2, default would using v1 docker-compose
DOCKER_COMPOSE=podman-compose

while [ $# -gt 0 ]; do
        case $1 in
            --help)
            note "$usage"
            exit 0;;
            --with-trivy)
            with_trivy=true;;
            *)
            note "$usage"
            exit 1;;
        esac
        shift || true
done

workdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export HARBOR_BUNDLE_DIR=$PWD

cd $workdir

mkdir -p common/config

if [ -f harbor*.tar.gz ]
then
    h2 "[Step $item]: loading Harbor images ..."; let item+=1
    docker load -i ./harbor*.tar.gz
fi
echo ""

h2 "[Step $item]: preparing environment ...";  let item+=1
if [ -n "$host" ]
then
    sed "s/^hostname: .*/hostname: $host/g" -i ./harbor.yml
fi

h2 "[Step $item]: preparing harbor configs ...";  let item+=1
prepare_para=
if [ $with_trivy ]
then
    prepare_para="${prepare_para} --with-trivy"
fi

./prepare $prepare_para
echo ""

if [ -n "$DOCKER_COMPOSE ps -q"  ]
    then
        note "stopping existing Harbor instance ..."
        $DOCKER_COMPOSE down -v
fi
echo ""

cd .

sed -i '/image: goharbor\/trivy-adapter-photon:v[0-9.]\+/a\ \ \ \ environment:\n\ \ \ \ \ \ - SCANNER_REDIS_URL=redis://redis:6379' docker-compose.yml
sed -i \
  's|/var/log/harbor/:/var/log/docker/:z|./log:/var/log/docker/:z|' \
  docker-compose.yml
sed -i \
  's|\./common/config|./common/config|g' \
  docker-compose.yml

# Mark the start of each logging: block and the line just before the next service
sed -i \
  -e '/^[[:space:]]\{4\}logging:/i __LOG_BLOCK_START__' \
  -e '/^  [[:alnum:]_-]\+:/i __LOG_BLOCK_END__' \
  docker-compose.yml

# Delete from each start‑marker through its end‑marker
sed -i '/__LOG_BLOCK_START__/,/__LOG_BLOCK_END__/d' docker-compose.yml

# Remove any leftover markers
sed -i '/__LOG_BLOCK_/d' docker-compose.yml

# Fix docker-compose for podman - Delete from the first “networks:” line through EOF
sed -i '/^networks:/,$d' docker-compose.yml

# Append a simple harbor network definition
cat << 'EOF' >> docker-compose.yml

networks:
  harbor:
EOF


h2 "[Step $item]: starting Harbor ..."
$DOCKER_COMPOSE up -d

success $"----Harbor has been installed and started successfully.----"
