#!/bin/bash -e
#!/usr/bin/env bash

KUBE_FLAG=""
if
  [ "$1" = "--minikube" ] || [ "$1" = "-m" ]; then
  KUBE_FLAG="-m"
fi


echo "Build pulp/pulpcore images"
cd $GITHUB_WORKSPACE/containers/
cp $GITHUB_WORKSPACE/.ci/ansible/vars.yaml vars/vars.yaml
sed -i "s/podman/docker/g" common_tasks.yaml
pip install ansible

if [[ -z "${QUAY_EXPIRE+x}" ]]; then
  ansible-playbook -v build.yaml
else
  sed -i "s/latest/${QUAY_IMAGE_TAG}/g" vars/vars.yaml
  echo "Building tag: ${QUAY_IMAGE_TAG}"
  ansible-playbook -v build.yaml --extra-vars "quay_expire=${QUAY_EXPIRE}"
fi
cd $GITHUB_WORKSPACE

echo "Deploy pulp latest"
sudo -E QUAY_REPO_NAME=pulp $GITHUB_WORKSPACE/.ci/scripts/quay-push.sh

echo "Deploy pulpcore latest"
sudo -E QUAY_REPO_NAME=pulpcore $GITHUB_WORKSPACE/.ci/scripts/quay-push.sh

echo "Deploy galaxy latest"
sudo -E QUAY_REPO_NAME=galaxy $GITHUB_WORKSPACE/.ci/scripts/quay-push.sh


echo "Build web images"
cd $GITHUB_WORKSPACE/containers/
cp $GITHUB_WORKSPACE/.ci/ansible/web/vars.yaml vars/vars.yaml
sed -i "s/podman/docker/g" common_tasks.yaml

if [[ -z "${QUAY_EXPIRE+x}" ]]; then
  ansible-playbook -v build.yaml
else
  sed -i "s/latest/${QUAY_IMAGE_TAG}/g" vars/vars.yaml
  echo "Building tag: ${QUAY_IMAGE_TAG}"
  ansible-playbook -v build.yaml --extra-vars "quay_expire=${QUAY_EXPIRE}"
fi
cd $GITHUB_WORKSPACE

echo "Test pulp/pulpcore images"
if [[ -n "${QUAY_EXPIRE}" ]]; then
  echo "LABEL quay.expires-after=${QUAY_EXPIRE}d" >> ./build/Dockerfile
fi
sudo -E ./up.sh
.ci/scripts/pulp-operator-check-and-wait.sh $KUBE_FLAG
.ci/scripts/retry.sh 3 ".ci/scripts/pulp_file-tests.sh -m"

docker images

echo "Deploy pulp-web latest"
sudo -E QUAY_REPO_NAME=pulp-web $GITHUB_WORKSPACE/.ci/scripts/quay-push.sh

echo "Deploy galaxy-web latest"
sudo -E QUAY_REPO_NAME=galaxy-web $GITHUB_WORKSPACE/.ci/scripts/quay-push.sh

if [[ -z "${QUAY_EXPIRE+x}" ]]; then
  echo "Deploy pulp-operator"
  eval $(minikube -p minikube docker-env)
  sudo -E $GITHUB_WORKSPACE/.ci/scripts/quay-push.sh
fi
