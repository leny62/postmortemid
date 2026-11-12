FROM python:3.12-slim
RUN pip install --no-cache-dir uv==0.5.11
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY pmid_upload ./pmid_upload
RUN useradd --uid 1000 --no-create-home pmid
USER pmid
EXPOSE 8000
CMD ["/app/.venv/bin/uvicorn", "pmid_upload.app:app_from_env", "--factory", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
