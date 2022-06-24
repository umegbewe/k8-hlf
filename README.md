# k8-hlf

Script to automate setting up a simple hyperledger fabric with [hlf-operator](https://github.com/hyperledger-labs/hlf-operator)

Executed:

* Ordering service with a node and a CA
* Peer organization with 2 peer both using levelDB and a CA
* A channel (my-channel1)
* A chaincode (chaincode1) installed in peer0
* A chaincode approved and committed

### Run:
```
./k8.sh up
```

### Invoke a transaction in the ledger
```
kubectl hlf chaincode invoke --config=org1.yaml \
    --user=admin --peer=org1-peer0.default \
    --chaincode=chaincode1 --channel=my-channel1 \
    --fcn=initLedger -a '[]'
```

### Query the ledger
```
kubectl hlf chaincode query --config=org1.yaml \
    --user=admin --peer=org1-peer0.default \
    --chaincode=chaincode1 --channel=my-channel1 \
    --fcn=GetAllAssets -a '[]'
```

### Cleanup created resources:
```
./k8.sh down
```
