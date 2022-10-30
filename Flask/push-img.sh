#!/bin/bash

while getopts t:c flag
do
    case "${flag}" in
        t) tag=${OPTARG};;
        c) cache=1;;
    esac
done

if [ -z "$cache" ]
then
    docker build --no-cache -t tagger-api:$tag .
else
    docker build -t tagger-api:$tag .
fi

docker tag tagger-api:$tag oldcoyote03/tagger-api:$tag
docker push oldcoyote03/tagger-api:$tag