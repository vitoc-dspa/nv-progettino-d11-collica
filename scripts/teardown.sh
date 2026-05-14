#!/usr/bin/env bash
sudo docker-compose down
sudo rm -rf open_webui_mount
sudo rm -rf pgvector_data_mount
sudo rm -rf ollama_mount
sudo rm -rf caddy_data_mount
sudo rm -rf caddy_config_mount