#!/bin/bash
ERROR_FILE="/tmp/docker-image-update.error"

# make sure that docker is running
DOCKER_INFO_OUTPUT=$(docker info 2> /dev/null | grep "Containers:" | awk '{print $1}')

if [ "$DOCKER_INFO_OUTPUT" == "Containers:" ]
  then
    echo "Docker is running, so we can continue"
  else
    echo "Docker is not running, exiting"
    exit 1
fi

IMAGE="$1"

echo "*****"
echo "Updating $IMAGE"
docker pull $IMAGE 2> $ERROR_FILE
if [ $? != 0 ]; then
  ERROR=$(cat $ERROR_FILE | grep "not found")
  if [ "$ERROR" != "" ]; then
    echo "WARNING: Docker image $IMAGE not found in repository, skipping"
  else
    echo "ERROR: docker pull failed on image - $IMAGE"
    exit 2
  fi
fi
echo "*****"
echo

# did everything finish correctly? Then we can exit
echo "Docker image $IMAGE are now up to date"
exit 0