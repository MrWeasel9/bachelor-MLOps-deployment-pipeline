import mlflow
import numpy as np
import os
from sklearn import datasets, metrics
from sklearn.linear_model import ElasticNet
from sklearn.model_selection import train_test_split


def eval_metrics(pred, actual):
    rmse = np.sqrt(metrics.mean_squared_error(actual, pred))
    mae = metrics.mean_absolute_error(actual, pred)
    r2 = metrics.r2_score(actual, pred)
    return rmse, mae, r2


# Use the MLFLOW_TRACKING_URI from the environment, which is set by the Kubernetes Job
mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI"))

# Set the experiment name
mlflow.set_experiment("wine-quality")

# Enable auto-logging to MLflow
mlflow.sklearn.autolog()

# Load wine quality dataset
X, y = datasets.load_wine(return_X_y=True)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.25, random_state=42)

# Start a run and train a model
with mlflow.start_run(run_name="default-params"):
    lr = ElasticNet(random_state=42)
    lr.fit(X_train, y_train)

    y_pred = lr.predict(X_test)
    (rmse, mae, r2) = eval_metrics(y_pred, y_test)
    
    print(f"RMSE: {rmse}")
    print(f"MAE: {mae}")
    print(f"R2: {r2}")
    print("Model trained and logged to MLflow successfully!")
