#!/bin/bash

STORAGE_CLASS=${STORAGE_CLASS:-}

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

os::test::junit::declare_suite_start "$MY_SCRIPT"

checkCreate() {
  local corename
  local frontname

  # Make sure we've only got 1 (in case we ran in a dirty namespace)
  os::cmd::try_until_text "oc get pods --no-headers -l app.kubernetes.io/name=perceptilabs-core 2> /dev/null | wc -l" '^1$'
  os::cmd::try_until_text "oc get pods --no-headers -l app.kubernetes.io/name=perceptilabs-frontend 2> /dev/null | wc -l" '^1$'

  # Make sure the lists are fully populaed, sometimes "items" is not immediately populated
  os::cmd::try_until_success "oc get pod -l app.kubernetes.io/name=perceptilabs-core -o jsonpath='{.items[0].metadata.name}'"
  corename=$(oc get pod -l app.kubernetes.io/name=perceptilabs-core -o jsonpath="{.items[0].metadata.name}")
  os::cmd::try_until_success "oc get pod -l app.kubernetes.io/name=perceptilabs-frontend -o jsonpath='{.items[0].metadata.name}'"
  frontname=$(oc get pod -l app.kubernetes.io/name=perceptilabs-frontend -o jsonpath="{.items[0].metadata.name}")

  os::cmd::try_until_text "oc get pod $corename -o jsonpath='{.status.containerStatuses[?(@.name==\"core\")].ready}'" "true"
  os::cmd::try_until_text "oc get pod $frontname -o jsonpath='{.status.containerStatuses[?(@.name==\"frontend\")].ready}'" "true"
  os::cmd::try_until_success "oc get configmap perceptilabs-license"
  os::cmd::try_until_success "oc get service perceptilabs-core"
  os::cmd::try_until_success "oc get service perceptilabs-frontend"
  os::cmd::try_until_success "oc get route perceptilabs-core"
  os::cmd::try_until_success "oc get route perceptilabs-frontend"

  # If the endpoint list is non-null then services successfully mapped to pods
  os::cmd::try_until_not_text "oc get endpoints perceptilabs-core -o=jsonpath='{.subsets}' | wc -c" '^0$'
  os::cmd::try_until_not_text "oc get endpoints perceptilabs-frontend -o=jsonpath='{.subsets}' | wc -c" '^0$'

  host=$(oc get route perceptilabs-frontend -o jsonpath="{.spec.host}")
  os::cmd::try_until_text "curl $host" "PerceptiLabs"
}

checkVolume() {
  local name
  name=$(oc get pod  -l app.kubernetes.io/name=perceptilabs-core -o jsonpath="{.items[0].metadata.name}")
  os::cmd::expect_success_and_text "oc get pod $name -o jsonpath='{.spec.volumes[?(@.name==\"core-data-volume\")].persistentVolumeClaim.claimName}'" "perceptilabs-pvc"
  os::cmd::expect_success_and_text "oc get pod $name -o jsonpath='{.spec.containers[?(@.name==\"core\")].volumeMounts[?(@.name==\"core-data-volume\")]}'" "core-data-volume"
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
  os::cmd::try_until_text "oc get pods --no-headers -l app=perceptilabs 2> /dev/null | wc -l" '^0$'
  os::cmd::try_until_failure "oc get configmap perceptilabs-license"
  os::cmd::try_until_failure "oc get service perceptilabs-core"
  os::cmd::try_until_failure "oc get service perceptilabs-frontend"
  os::cmd::try_until_failure "oc get route perceptilabs-core"
  os::cmd::try_until_failure "oc get route perceptilabs-frontend"
  os::cmd::try_until_text "oc get perceptilabs --no-headers 2> /dev/null | wc -l" '^0$'
}

makePVC() {
  # If there are no storage classes defined, assume something like a CRC environment
  # with predefined PVs and just create a PVC without storageclass specified.
  # Similarly, if there is a default storageclass, just create a PVC with no storageclass
  sc=$(oc get storageclass --no-headers 2>/dev/null)
  set +e
  def=$(echo $sc | grep "\(default\)")
  set -e
  if [ -n "$STORAGE_CLASS" ]; then
      set +e
      oc get storageclass "$STORAGE_CLASS" &> /dev/null
      res=$?
      set -e
      if [ "$res" != 0 ]; then
          echo Storage class $STORAGE_CLASS does not exit, exiting
          exit 1
      else
          echo Use custom storage class $STORAGE_CLASS for pvc
          sed "s/STORAGE_CLASS/$STORAGE_CLASS/" $MY_DIR/manifests/pvc-sc.yaml | oc create -f -
      fi
  elif [ "$def" != "" ]; then
      # Storage classes defined, and there is a default, just create the pvc
      # with no specific class
      echo Creating PVC with default storage class
      oc create -f $MY_DIR/manifests/pvc.yaml
  elif [ "$sc" == "" ]; then
      # No storage classes defined, let's see if there are available PVs
      echo No storage classes defined, assuming available PVs with no specified storageclass
      oc create -f $MY_DIR/manifests/pvc.yaml
  fi
}

# make sure we're not starting with any perceptilabs
# make sure we're not starting with a pvc
set +e
testDelete
oc delete pvc perceptilabs-pvc 2> /dev/null
os::cmd::try_until_failure "oc get pvc perceptilabs-pvc"
set -e

testCreateNoPVC
testDelete

makePVC
testCreateWithPVC
testDelete

# cleanup the pvc
oc delete pvc perceptilabs-pvc

os::test::junit::declare_suite_end
