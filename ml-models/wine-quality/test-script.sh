MASTER=34.116.194.243
curl -X POST \
     -H 'Content-Type: application/json' \
     -d @wine.json \
     http://${MASTER}:32255/models/mlflow-wine-classifier/infer
