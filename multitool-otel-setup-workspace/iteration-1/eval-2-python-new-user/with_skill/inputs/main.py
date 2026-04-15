import tracing  # noqa: F401 - must be imported before FastAPI
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}
