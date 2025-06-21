
#!/usr/bin/env python3
"""Async load tester for a KServe / MLServer endpoint that prints every response.

Fires <rate> requests per minute in total, split across <concurrency> async workers.

Example:
    python load_test.py --host 34.118.48.46 --model mlflow-model --rate 100 --minutes 5
"""

import asyncio
import aiohttp
import argparse
import random
import time
from typing import List

FEATURE_RANGES = [
    (11.0, 15.0),   # Alcohol
    (0.7, 5.8),     # Malic acid
    (1.3, 3.3),     # Ash
    (10.0, 30.0),   # Alcalinity of ash
    (70.0, 162.0),  # Magnesium
    (0.9, 4.0),     # Total phenols
    (0.3, 5.1),     # Flavanoids
    (0.1, 0.7),     # Nonflavanoid phenols
    (0.4, 3.6),     # Proanthocyanins
    (1.0, 13.0),    # Color intensity
    (0.4, 1.8),     # Hue
    (1.2, 4.0),     # OD280/OD315
    (278.0, 1680.0) # Proline
]

def random_sample() -> List[float]:
    """Return one random wine sample as a list of 13 floats."""
    return [round(random.uniform(low, high), 3) for low, high in FEATURE_RANGES]

def build_body(sample: List[float]):
    """JSON body understood by MLServer with NumPy codec."""
    return {
        "parameters": {"content_type": "np"},
        "inputs": [{
            "name": "input",
            "datatype": "FP32",
            "shape": [1, 13],
            "data": sample
        }]
    }

async def worker(session: aiohttp.ClientSession, url: str, interval: float, stop: float, wid: int):
    req_id = 0
    while time.time() < stop:
        body = build_body(random_sample())
        try:
            async with session.post(url, json=body, timeout=30) as r:
                try:
                    resp_json = await r.json(content_type=None)
                except aiohttp.ContentTypeError:
                    resp_json = await r.text()
                print(f"[worker {wid} | {req_id}] status={r.status} → {resp_json}")
        except Exception as exc:
            print(f"[worker {wid} | {req_id}] ERROR {exc}")
        req_id += 1
        await asyncio.sleep(interval)

async def main(host: str, model: str, rate: int, minutes: int, concurrency: int):
    url = f"http://{host}:32255/models/{model}/infer"
    per_worker_rate = max(rate / concurrency, 1)
    interval = 60.0 / per_worker_rate
    stop = time.time() + minutes * 60

    async with aiohttp.ClientSession() as session:
        tasks = [
            asyncio.create_task(worker(session, url, interval, stop, wid))
            for wid in range(concurrency)
        ]
        await asyncio.gather(*tasks)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True, help="Inference endpoint host or IP")
    parser.add_argument("--model", default="mlflow-model", help="Model name in the URL")
    parser.add_argument("--rate", type=int, default=100, help="Total requests per minute")
    parser.add_argument("--minutes", type=int, default=1, help="Test duration in minutes")
    parser.add_argument("--concurrency", type=int, default=10, help="Number of async workers")
    args = parser.parse_args()

    try:
        asyncio.run(main(args.host, args.model, args.rate, args.minutes, args.concurrency))
    except KeyboardInterrupt:
        pass
