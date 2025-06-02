# MLOps CI/CD Pipeline Example (GCP)

This repository contains an end‑to‑end example of a CI/CD pipeline for training, packaging and deploying an ML model (Iris classifier) to **Google Kubernetes Engine (GKE)**.

## Folder structure
| Path | Description |
|------|-------------|
| **ml/** | Training script (`train.py`), FastAPI inference service (`app.py`) & Python deps |
| **docker/** | Dockerfile for the inference image |
| **ci/** | `Jenkinsfile` defining the pipeline |
| **infra/** | Terraform code – GKE cluster & supporting resources |
| **k8s/** | Kubernetes manifests: `Deployment`, `Service`, `HPA` |
| **tests/** | Basic unit/integration tests |

## Quick start (local smoke‑test)

```bash
# Clone repo & enter
git clone <your‑repo‑url>
cd mlops_ci_cd

# Train locally
pip install -r ml/requirements.txt
python ml/train.py

# Build & run the API locally
docker build -f docker/Dockerfile -t iris-api:dev .
docker run -p 8000:8000 iris-api:dev
```
