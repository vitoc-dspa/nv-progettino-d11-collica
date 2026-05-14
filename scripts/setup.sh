#!/usr/bin/env bash
sudo docker-compose pull
sudo docker-compose up -d
sudo docker compose exec ollama ollama pull qwen3.5:2b