import mlflow
import numpy as np
import os
from sklearn import datasets, metrics
from sklearn.linear_model import ElasticNet
from sklearn.model_selection import train_test_split, RandomizedSearchCV
from scipy.stats import uniform

def eval_metrics(pred, actual):
    rmse = np.sqrt(metrics.mean_squared_error(actual, pred))
    mae = metrics.mean_absolute_error(actual, pred)
    r2 = metrics.r2_score(actual, pred)
    return rmse, mae, r2

# Use the MLFLOW_TRACKING_URI from the environment
mlflow.set_tracking_uri(os.environ.get("MLFLOW_TRACKING_URI"))

# Load wine quality dataset
X, y = datasets.load_wine(return_X_y=True)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.25, random_state=42)

# Set the experiment name
mlflow.set_experiment("wine-quality")
# Disable autologging for the top-level model to log it manually
mlflow.sklearn.autolog(log_models=False, log_datasets=False) 

lr = ElasticNet(random_state=42)

# Define distribution to pick parameter values from
distributions = dict(
    alpha=uniform(loc=0, scale=10),
    l1_ratio=uniform(),
)

# Initialize random search instance
clf = RandomizedSearchCV(
    estimator=lr,
    param_distributions=distributions,
    scoring="neg_mean_absolute_error",
    cv=5,
    n_iter=100,
    random_state=42
)

# Start a parent run
with mlflow.start_run(run_name="hyperparameter-tuning") as parent_run:
    search = clf.fit(X_train, y_train)

    # Log the best model from the search to the parent run
    mlflow.sklearn.log_model(clf.best_estimator_, "model")

    # Evaluate the best model on test dataset and log metrics
    y_pred = clf.best_estimator_.predict(X_test)
    (rmse, mae, r2) = eval_metrics(y_pred, y_test)
    mlflow.log_metrics(
        {
            "rmse_test": rmse,
            "mae_test": mae,
            "r2_test": r2,
        }
    )
    
    # Save the parent run ID to a file for the pipeline to retrieve
    parent_run_id = parent_run.info.run_id
    with open("/tmp/run_id.txt", "w") as f:
        f.write(parent_run_id)
    
    print(f"Best parameters: {clf.best_params_}")
    print(f"Best test R2 score: {r2}")
    print(f"Hyperparameter tuning completed and logged to MLflow!")
    print(f"Run ID {parent_run_id} saved to /tmp/run_id.txt")
