FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY John-Deere-Multi-Agent-System/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY John-Deere-Multi-Agent-System/ ./
RUN useradd --create-home app
USER app
EXPOSE 8080 8765
ENTRYPOINT ["python", "Servidor/server.py"]
CMD ["--host", "0.0.0.0", "--web-port", "8080", "--autostart", "--rows", "16", "--cols", "22", "--harvesters", "4", "--carts", "2", "--delay", "1.0"]
