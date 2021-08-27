#!/usr/bin/env bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}")" && pwd )
kubectl create -f ${DIR}/manifests/setup
until kubectl get servicemonitors --all-namespaces ; do date; sleep 5; echo ""; done  # setup 资源创建完毕后，等待5秒 (让先决资源初始化完成)
kubectl create -f ${DIR}/manifests/
