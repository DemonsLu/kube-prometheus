#!/usr/bin/env bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )
kubectl delete --ignore-not-found=true -f ${DIR}/manifests/ -f ${DIR}/manifests/setup
