FROM python:3.12-slim
WORKDIR /app
# Prod EC2: requirements.prod.txt (rápido). Dev completo: requirements.txt (D-Wave/Braket opt-in).
ARG REQUIREMENTS_FILE=requirements.prod.txt
COPY ${REQUIREMENTS_FILE} requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
ENV PYTHONUNBUFFERED=1
ENV ROUTE_OPT_SOLVER=greedy
ENV DISABLE_DWAVE=1
ENV USE_AMAZON_BRAKET=0
EXPOSE 8787
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8787"]
