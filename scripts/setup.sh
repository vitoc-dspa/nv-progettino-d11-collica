#!/usr/bin/env bash
sudo docker-compose pull
# Crea certificato SSL self-signed in certs_mount (key.key + cert.crt)
sudo mkdir -p certs_mount
sudo openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout certs_mount/key.key \
  -out certs_mount/cert.crt \
  -subj "/CN=localhost"

sudo chmod 600 certs_mount/key.key
sudo chmod 644 certs_mount/cert.crt
sudo docker-compose up -d
sudo docker compose exec ollama ollama pull qwen3.5:2b