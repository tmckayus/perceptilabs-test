#!/bin/bash

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

os::test::junit::declare_suite_start "$MY_SCRIPT"

checkCreate() {
  os::cmd::try_until_text "oc get pod -l app.kubernetes.io/name=perceptilabs-frontend -o yaml" 'ready: true'
  os::cmd::try_until_text "oc get pod -l app.kubernetes.io/name=perceptilabs-core -o yaml" 'ready: true'
  os::cmd::try_until_success "oc get configmap perceptilabs-license"
  os::cmd::try_until_success "oc get service perceptilabs-core"
  os::cmd::try_until_success "oc get service perceptilabs-frontend"
  os::cmd::try_until_success "oc get route perceptilabs-core"
  os::cmd::try_until_success "oc get route perceptilabs-frontend"  
  # test that the selector for the service matches the pod? or test for the creation of an endpoint?
  # test that the route matches the servicename
}

checkVolume() {
    echo check volume not implemented yet
}

testCreateWithPVC() {
  os::cmd::expect_success_and_text "oc create -f $MY_DIR/manifests/withpvc.yaml" 'perceptilabs.perceptilabs.com/example-perceptilabs created'
  checkCreate
  checkVolume
}

testCreateNoPVC() {
  os::cmd::expect_success_and_text "oc create -f $MY_DIR/manifests/nopvc.yaml" 'perceptilabs.perceptilabs.com/example-perceptilabs-nopvc created'
  checkCreate
}

testDelete() {
  os::cmd::expect_success "oc delete perceptilabs --all"
  os::cmd::try_until_text "oc get pods --no-headers -l app=perceptilabs 2> /dev/null | wc -l" '0'
  os::cmd::try_until_failure "oc get configmap perceptilabs-license"
  os::cmd::try_until_failure "oc get service perceptilabs-core"
  os::cmd::try_until_failure "oc get service perceptilabs-frontend"
  os::cmd::try_until_failure "oc get route perceptilabs-core"
  os::cmd::try_until_failure "oc get route perceptilabs-frontend"
  os::cmd::try_until_text "oc get perceptilabs --no-headers 2> /dev/null | wc -l" '0'
}

# make sure we're not starting with any perceptilabs
# make sure we're not starting with a pvc
set +e
oc delete perceptilabs --all
os::cmd::try_until_text "oc get perceptilabs --no-headers 2> /dev/null | wc -l" '0'
oc delete pvc perceptilabs-pvc
os::cmd::try_until_failure "oc get pvc perceptilabs-pvc"
set -e

testCreateNoPVC
testDelete

oc create -f $MY_DIR/manifests/pvc.yaml
testCreateWithPVC
testDelete

# cleanup the pvc
oc delete pvc perceptilabs-pvc

os::test::junit::declare_suite_end
