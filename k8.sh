#!/bin/bash

set -e


source ./chaincode.sh

# global variables

BLUE="$(printf '\033[34m')"

NAMESPACE=default
VERSION="1.0"
SEQUENCE=1

REPOSITORY="https://kfsoftware.github.io/hlf-helm-charts"
ORG=org1
ORD=orderer
MSP_ORG=Org1MSP
MSP_ORD=OrdererMSP

PEER_IMAGE=hyperledger/fabric-peer
PEER_VERSION=2.4.3
PEER_SECRET=peerpw

ORDERER_IMAGE=hyperledger/fabric-orderer
ORDERER_VERSION=2.4.3
ORDERER_SECRET=ordererpw

CHANNEL=my-channel1

STORAGE_CLASS=$(kubectl describe sc | grep Name | tr -s ' ' | cut -d ':' -f 2 | cut -d ' ' -f 2)
ID=enroll
SECRET=enrollpw


up() {
    install && \
    ca && \
    peer && \
    orderer && \
    admin && \
    channel && \
    connect && \
    chaincode
}

down() {
    kubectl delete fabricorderernodes.hlf.kungfusoftware.es --all-namespaces --all
    kubectl delete fabricpeers.hlf.kungfusoftware.es --all-namespaces --all
    kubectl delete fabriccas.hlf.kungfusoftware.es --all-namespaces --all
    kubectl delete fabricchaincode.hlf.kungfusoftware.es --all-namespaces --all
}

install() {
helm repo add kfs $REPOSITORY --force-update

helm install hlf-operator --version=1.6.0 kfs/hlf-operator

while [ "$(kubectl get pods -l=app.kubernetes.io/name=hlf-operator -o jsonpath='{.items[*].status.containerStatuses[0].ready}')" != "true" ]; do
   sleep 5
   echo $BLUE "Waiting for Operator to be ready."
done
}


ca() {

    kubectl hlf ca create --storage-class=$STORAGE_CLASS --capacity=2Gi --name=$ORG-ca --enroll-id=$ID --enroll-pw=$SECRET && sleep 3

    while [[ $(kubectl get pods -l release=$ORG-ca -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do 
        sleep 5 
        echo $BLUE "waiting for CA" 
    done

    kubectl hlf ca register --name=$ORG-ca --user=peer --secret=$PEER_SECRET --type=peer --enroll-id $ID --enroll-secret=$SECRET --mspid $MSP_ORG && \
    echo $BLUE "registered $ORG-ca" 
}

peer() {
    kubectl hlf peer create --image=$PEER_IMAGE --version=$PEER_VERSION --storage-class=$STORAGE_CLASS --enroll-id=peer --mspid=$MSP_ORG \
        --enroll-pw=$PEER_SECRET --capacity=5Gi --name=$ORG-peer0 --ca-name=$ORG-ca.$NAMESPACE
    kubectl hlf peer create --image=$PEER_IMAGE --version=$PEER_VERSION --storage-class=$STORAGE_CLASS --enroll-id=peer --mspid=$MSP_ORG \
        --enroll-pw=$PEER_SECRET --capacity=5Gi --name=$ORG-peer1 --ca-name=$ORG-ca.$NAMESPACE
        
    while [[ $(kubectl get pods -l app=hlf-peer --output=jsonpath='{.items[*].status.containerStatuses[0].ready}') != "true true" ]]; do 
        sleep 5
        echo $BLUE "waiting for peer nodes to be ready" 
    done
    
}

orderer() {
    kubectl hlf ca create --storage-class=$STORAGE_CLASS --capacity=2Gi --name=$ORD-ca --enroll-id=$ID --enroll-pw=$SECRET

    while [[ $(kubectl get pods -l release=$ORD-ca -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
        sleep 5
        echo $BLUE "waiting for $ORD CA to be ready"
    done

    kubectl hlf ca register --name=$ORD-ca --user=orderer --secret=$ORDERER_SECRET --type=orderer --enroll-id $ID --enroll-secret=$SECRET --mspid $MSP_ORD && \
    echo $BLUE "registered $ORD-ca"
    
    
    kubectl hlf ordnode create --image=$ORDERER_IMAGE --version=$ORDERER_VERSION \
    --storage-class=$STORAGE_CLASS --enroll-id=$ORD --mspid=$MSP_ORD \
    --enroll-pw=$ORDERER_SECRET --capacity=2Gi --name=$ORD-node1 --ca-name=$ORD-ca.$NAMESPACE
    
    while [[ $(kubectl get pods -l app=hlf-ordnode -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
        sleep 5
        echo $BLUE "waiting for $ORD Node to be ready"
    done
    
}

admin() {
    kubectl hlf inspect --output ordservice.yaml -o $MSP_ORD && \
    
    kubectl hlf ca register --name=$ORD-ca --user=admin --secret=$SECRET --type=admin --enroll-id $ID --enroll-secret=$SECRET --mspid=$MSP_ORD && \
    
    kubectl hlf ca enroll --name=$ORD-ca --user=admin --secret=$SECRET --mspid $MSP_ORD --ca-name ca  --output admin-ordservice.yaml && \
    
    kubectl hlf utils adduser --userPath=admin-ordservice.yaml --config=ordservice.yaml --username=admin --mspid=$MSP_ORD
}

channel() {
    kubectl hlf channel generate --output=$CHANNEL.block --name=$CHANNEL --organizations $MSP_ORG --ordererOrganizations $MSP_ORD && \
    
    kubectl hlf ca enroll --name=$ORD-ca --namespace=$NAMESPACE --user=admin --secret=$SECRET --mspid $MSP_ORD --ca-name tlsca --output admin-tls-ordservice.yaml && \
    
    kubectl hlf ordnode join --block=$CHANNEL.block --name=$ORD-node1 --namespace=$NAMESPACE --identity=admin-tls-ordservice.yaml
    
}

connect() {
    kubectl hlf ca register --name=$ORG-ca --user=admin --secret=$SECRET --type=admin --enroll-id $ID --enroll-secret=$SECRET --mspid $MSP_ORG && \
    
    kubectl hlf ca enroll --name=$ORG-ca --user=admin --secret=$SECRET --mspid $MSP_ORG --ca-name ca  --output peer-org1.yaml && \
    
    kubectl hlf inspect --output org1.yaml -o $MSP_ORG -o $MSP_ORD && \
    
    kubectl hlf utils adduser --userPath=peer-org1.yaml --config=org1.yaml --username=admin --mspid=$MSP_ORG && \
    
    sleep 10 && \
    
    kubectl hlf channel join --name=$CHANNEL --config=org1.yaml --user=admin -p=$ORG-peer0.$NAMESPACE && \

    kubectl hlf channel addanchorpeer --channel=$CHANNEL --config=org1.yaml --user=admin --peer=$ORG-peer0.$NAMESPACE
    
    kubectl hlf channel join --name=$CHANNEL --config=org1.yaml --user=admin -p=$ORG-peer1.$NAMESPACE
}


chaincode() {
    generateChaincode
    
    kubectl hlf chaincode install --path=./asset-transfer-basic-external.tgz \
    --config=org1.yaml --language=golang --label=$CHAINCODE_LABEL --user=admin --peer=$ORG-peer0.$NAMESPACE
    
    kubectl hlf chaincode install --path=./asset-transfer-basic-external.tgz \
    --config=org1.yaml --language=golang --label=$CHAINCODE_LABEL --user=admin --peer=$ORG-peer1.$NAMESPACE
    
    kubectl hlf chaincode approveformyorg --config=org1.yaml --user=admin --peer=$ORG-peer0.$NAMESPACE \
    --package-id=$PACKAGE_ID --version "$VERSION" --sequence "$SEQUENCE" --name=$CHAINCODE_NAME \
    --policy="OR('Org1MSP.member')" --channel=$CHANNEL
    
    kubectl hlf chaincode commit --config=org1.yaml --user=admin --mspid=$MSP_ORG \
    --version "$VERSION" --sequence "$SEQUENCE" --name=$CHAINCODE_NAME \
    --policy="OR('Org1MSP.member')" --channel=$CHANNEL
}

if [ "$1" = "up" ]; then
    up
elif [ "$1" = "down" ]; then
    down
else
    exit
fi
