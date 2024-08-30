#!/bin/bash

DISTRO=$1
ARCH=$2
INSTALL_COMMAND="wget -qO - https://raw.githubusercontent.com/msazanov/Z-WayInstallScript/stock/Z-Way-Install | sudo bash"
LOG_DIR="/opt/z-way-server/install_test_results"
SUMMARY_LOG="${LOG_DIR}/${DISTRO}-${ARCH}-summary.log"

# Создаем директорию для логов, если она не существует
mkdir -p $LOG_DIR

# Добавляем системную информацию в лог
{
    echo "System Information:"
    uname -a
    echo
    echo "/etc/os-release:"
    cat /etc/os-release
    echo
} > $SUMMARY_LOG

# Выполнение команды установки Z-Way сервера и запись в лог
bash -c "$INSTALL_COMMAND" >> $SUMMARY_LOG 2>&1

# Инициализация статуса и ошибок
STATUS="Провал"
ERRORS_FOUND=false
LIBRARIES=("libarchive" "libssl" "libc-ares" "libwebsockets" "libcurl" "libavahi")

# Проверка на критические ошибки и извлечение зависимостей
if grep -q "Depends: " $SUMMARY_LOG || grep -q "E: Unable to correct problems, you have held broken packages." $SUMMARY_LOG || grep -q "no packages found matching" $SUMMARY_LOG; then
    ERRORS_FOUND=true
    DEPENDENCIES=$(grep "Depends:" $SUMMARY_LOG | awk -F ": " '{print $2}' | awk '{print $1}' | sed 's/:armhf//g' | sed 's/:amd64//g')
fi

# Проверка на запуск z-way-server
if grep -q "Starting z-way-server: done." $SUMMARY_LOG; then
    if $ERRORS_FOUND; then
        STATUS="Сомнительно, но окей"
    else
        STATUS="Успех"
    fi

    # Останавливаем Z-Way сервер
    echo "Stopping Z-Way server..." >> $SUMMARY_LOG
    /etc/init.d/z-way-server stop >> $SUMMARY_LOG 2>&1

    # Проверяем, запущен ли процесс Z-Way сервера
    sleep 5
    if pgrep -x "z-way-server" > /dev/null; then
        echo "Z-Way server is still running, killing process..." >> $SUMMARY_LOG
        pkill -9 z-way-server
        echo "Process killed." >> $SUMMARY_LOG
    fi

    # Переход в папку с Z-Way сервером и выполнение команды
    echo "Navigating to /opt/z-way-server and listing contents..." >> $SUMMARY_LOG
    cd /opt/z-way-server/
    ls >> $SUMMARY_LOG 2>&1

    echo "Running Z-Way server manually with LD_LIBRARY_PATH..." >> $SUMMARY_LOG
    timeout 15s LD_LIBRARY_PATH=libs ./z-way-server >> $SUMMARY_LOG 2>&1 || echo "Z-Way server was stopped after timeout." >> $SUMMARY_LOG

    # Закрытие контейнера через 15 секунд
    echo "Closing container in 15 seconds..." >> $SUMMARY_LOG
    sleep 15
else
    STATUS="Провал"
fi

# Запись статуса в summary.log
{
    echo "======================================"
    echo "Дистрибутив: $DISTRO"
    echo "Архитектура: $ARCH"
    echo "Результат: $STATUS"
    echo "======================================"
} >> $SUMMARY_LOG

# Если есть ошибки, ищем доступные библиотеки
if $ERRORS_FOUND; then
    echo "Ошибки обнаружены, выполняется поиск доступных библиотек..." >> $SUMMARY_LOG

    for DEP in $DEPENDENCIES; do
        for LIB in "${LIBRARIES[@]}"; do
            if [[ $DEP == *"$LIB"* ]]; then
                echo "Поиск $LIB:" >> $SUMMARY_LOG
                apt search $LIB | grep -E "^(lib|$LIB)" | grep -v "^WARNING" >> $SUMMARY_LOG
            fi
        done
    done
fi

echo "======================================" >> $SUMMARY_LOG
