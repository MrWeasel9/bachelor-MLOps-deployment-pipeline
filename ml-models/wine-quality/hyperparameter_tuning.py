import mlflow
import numpy as np
from sklearn import datasets, metrics
from sklearn.linear_model import ElasticNet
from sklearn.model_selection import train_test_split, RandomizedSearchCV
from scipy.stats import uniform


def eval_metrics(actual, pred):
    rmse = np.sqrt(metrics.mean_squared_error(actual, pred))
    mae = metrics.mean_absolute_error(actual, pred)
    r2 = metrics.r2_score(actual, pred)
    return rmse, mae, r2


# Set the MLflow tracking URI to your cluster
# Replace with your actual master external IP
mlflow.set_tracking_uri("http://34.116.205.52:32255/mlflow/")

# Set the experiment name
mlflow.set_experiment("wine-quality")

# Enable auto-logging to MLflow
mlflow.sklearn.autolog()

# Load wine quality dataset
X, y = datasets.load_wine(return_X_y=True)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.25)

lr = ElasticNet()

# Define distribution to pick parameter values from
distributions = dict(
    alpha=uniform(loc=0, scale=10),  # sample alpha uniformly from [0, 10]
    l1_ratio=uniform(),  # sample l1_ratio uniformly from [0, 1.0]
)

# Initialize random search instance
clf = RandomizedSearchCV(
    estimator=lr,
    param_distributions=distributions,
    # Optimize for mean absolute error
    scoring="neg_mean_absolute_error",
    # Use 5-fold cross validation
    cv=5,
    # Try 100 samples. Note that MLflow only logs the top 5 runs.
    n_iter=100,
)

# Start a parent run
with mlflow.start_run(run_name="hyperparameter-tuning"):
    search = clf.fit(X_train, y_train)

    # Evaluate the best model on test dataset
    y_pred = clf.best_estimator_.predict(X_test)
    rmse, mae, r2 = eval_metrics(y_test, y_pred)
    
    mlflow.log_metrics(
        {
            "mean_squared_error_X_test": rmse,
            "mean_absolute_error_X_test": mae,
            "r2_score_X_test": r2,
        }
    )
    
    print(f"Best parameters: {clf.best_params_}")
    print(f"Best RMSE: {rmse}")
    print(f"Best MAE: {mae}")
    print(f"Best R2: {r2}")
    print("Hyperparameter tuning completed and logged to MLflow!")