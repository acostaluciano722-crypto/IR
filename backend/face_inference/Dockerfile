FROM python:3.12-slim-bookworm

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    DEEPFACE_BACKEND_ENGINE=onnx DEEPFACE_HOME=/models \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1

RUN groupadd --gid 10001 face \
    && useradd --uid 10001 --gid face --create-home face \
    && mkdir -p /models /app \
    && chown -R face:face /models /app
WORKDIR /app
COPY requirements.txt requirements.lock.txt ./
RUN python -m pip install --no-cache-dir -r requirements.lock.txt
COPY --chown=face:face service.py test_service.py ./
USER face
EXPOSE 5005
CMD ["gunicorn", "service:app", "--bind", "0.0.0.0:5005", "--workers", "1", "--threads", "2", "--timeout", "90", "--access-logfile", "-", "--error-logfile", "-"]
