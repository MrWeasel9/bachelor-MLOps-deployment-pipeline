EXTERNAL_IP=34.116.194.243      # your master-node public IP
NODE_PORT=32080                 # from step 1

curl -X POST \
     -H "Content-Type: application/json" \
     -d @wine.json \
     http://${EXTERNAL_IP}:${NODE_PORT}/v2/models/mlflow-wine-classifier/infer
