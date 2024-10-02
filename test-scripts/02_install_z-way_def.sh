#!/bin/bash

# Устанавливаем таймаут (например, 10 минут)
TIMEOUT=600

# Папка для логов
LOG_DIR="/tests/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/02_install_z-way_def.log"

# Выводим сообщение о начале выполнения теста
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Starting RaspbianInstall script..." | tee -a "$LOG_FILE"

# Проверяем текущего пользователя
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Current user: $(whoami)" | tee -a "$LOG_FILE"

# Проверяем наличие wget и sudo
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Checking for wget and sudo..." | tee -a "$LOG_FILE"
which wget | tee -a "$LOG_FILE"
which sudo | tee -a "$LOG_FILE"

# Выводим PATH для отладки
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Current PATH: $PATH" | tee -a "$LOG_FILE"

# Проверяем сетевое подключение
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Testing network connectivity..." | tee -a "$LOG_FILE"
ping -c 3 google.com | tee -a "$LOG_FILE" || echo "Network connectivity issue." | tee -a "$LOG_FILE"

# Выполняем команду с таймаутом и логированием
echo "[$(date +"%Y-%m-%d %H:%M:%S")] Executing RaspbianInstall script..." | tee -a "$LOG_FILE"
if timeout "$TIMEOUT" wget -qO - https://storage.z-wave.me/RaspbianInstall | sudo bash 2>&1 | tee -a "$LOG_FILE"; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] RaspbianInstall script completed successfully." | tee -a "$LOG_FILE"
    exit 0
else
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] RaspbianInstall script failed or timed out." | tee -a "$LOG_FILE"
    exit 1
fi
