#!/bin/sh
# Этот скрипт устанавливает, обновляет или удаляет TorrServer на OpenWRT.

# Каталог для TorrServer
dir="/opt/torrserver"
binary="${dir}/torrserver"
init_script="/etc/init.d/torrserver"

# Функция получения последней версии с GitHub
get_latest_version() {
    # Получаем URL последнего релиза через редирект
    latest_url=$(wget --spider --server-response "https://github.com/YouROK/TorrServer/releases/latest" 2>&1 | grep "Location:" | tail -1 | awk '{print $2}' | tr -d '\r')
    
    if [ -n "$latest_url" ]; then
        # Извлекаем версию из URL
        version=$(echo "$latest_url" | awk -F'/tag/' '{print $2}' | tr -d '\r')
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    echo "неизвестно"
}

# Функция удаления
remove_torrserver() {
    echo "Удаляем TorrServer..."
    
    # Останавливаем службу
    if [ -f "${init_script}" ]; then
        echo "Останавливаем службу..."
        ${init_script} stop
        ${init_script} disable
    fi
    
    # Удаляем бинарный файл
    if [ -f "${binary}" ]; then
        echo "Удаляем бинарный файл..."
        rm -f ${binary}
    fi
    
    # Удаляем init.d скрипт
    if [ -f "${init_script}" ]; then
        echo "Удаляем init.d скрипт..."
        rm -f ${init_script}
    fi
    
    # Спрашиваем про удаление каталога с данными
    if [ -d "${dir}" ]; then
        echo -n "Удалить каталог с данными ${dir}? (y/n): "
        read answer
        case "$answer" in
            [Yy]*)
                echo "Удаляем каталог с данными..."
                rm -rf ${dir}
                ;;
            *)
                echo "Каталог ${dir} сохранен"
                ;;
        esac
    fi
    
    echo "TorrServer успешно удален."
    exit 0
}

# Проверяем параметры командной строки
case "$1" in
    --remove|-r)
        remove_torrserver
        ;;
    --help|-h)
        echo "Использование: $0 [опции]"
        echo "Опции:"
        echo "  (без опций)     Установить или обновить TorrServer"
        echo "  --remove, -r    Удалить TorrServer"
        echo "  --help, -h      Показать эту справку"
        exit 0
        ;;
esac

# Проверяем, установлен ли TorrServer
if [ ! -f "${binary}" ]; then
    echo "TorrServer не установлен."
    echo "Начинаем установку..."
    
    # Создаем каталог
    mkdir -p ${dir}
else
    # Показываем текущую версию
    current_version=$(${binary} --version 2>/dev/null | head -n1 | sed 's/^TorrServer //')
    echo "Текущая версия TorrServer: ${current_version}"
    
    # Проверяем последнюю версию
    echo "Проверяем последнюю версию на GitHub..."
    latest_version=$(get_latest_version)
    
    if [ "$latest_version" != "неизвестно" ]; then
        echo "Последняя версия на GitHub: ${latest_version}"
        
        # Сравниваем версии (простое строковое сравнение)
        if [ "${current_version}" = "${latest_version}" ]; then
            echo "У вас уже установлена последняя версия."
            echo -n "Всё равно хотите обновить? (y/n): "
            read answer
            case "$answer" in
                [Yy]*)
                    echo "Принудительное обновление..."
                    ;;
                *)
                    echo "Обновление отменено."
                    exit 0
                    ;;
            esac
        else
            echo "Доступна новая версия!"
            echo -n "Хотите обновить с ${current_version} до ${latest_version}? (y/n): "
            read answer
            case "$answer" in
                [Yy]*)
                    echo "Обновляем TorrServer..."
                    ;;
                *)
                    echo "Обновление отменено."
                    exit 0
                    ;;
            esac
        fi
    else
        echo "Не удалось проверить последнюю версию на GitHub."
        echo -n "Хотите обновить вслепую? (y/n): "
        read answer
        case "$answer" in
            [Yy]*)
                echo "Обновляем TorrServer..."
                ;;
            *)
                echo "Обновление отменено."
                exit 0
                ;;
        esac
    fi
    
    # Останавливаем службу перед обновлением
    if [ -f "${init_script}" ]; then
        echo "Останавливаем службу..."
        ${init_script} stop
    fi
    # Удаляем старый бинарный файл
    echo "Удаляем старую версию..."
    rm -f ${binary}
fi

# Определяем архитектуру системы
echo "Определяем архитектуру системы..."
architecture=""
case $(uname -m) in
    x86_64) architecture="amd64" ;;
    i*86) architecture="386" ;;
    armv7*|armv6l) architecture="arm7" ;;
    armv5*) architecture="arm5" ;;
    aarch64|armv8) architecture="arm64" ;;
    mips) architecture="mips" ;;
    mips64) architecture="mips64" ;;
    mips64el) architecture="mips64le" ;;
    mipsel) architecture="mipsle" ;;
    *) echo "Архитектура не поддерживается: $(uname -m)"; exit 1 ;;
esac

echo "Архитектура: ${architecture}"

# Загружаем новую версию
url="https://github.com/YouROK/TorrServer/releases/latest/download/TorrServer-linux-${architecture}"
echo "Загружаем новую версию с GitHub..."
wget -O ${binary} ${url} --no-check-certificate --timeout=30 || {
    echo "Ошибка загрузки TorrServer"
    exit 1
}

# Делаем файл исполняемым
chmod +x ${binary}

# Проверяем, что файл загрузился
if [ ! -s "${binary}" ]; then
    echo "Ошибка: загруженный файл пуст"
    exit 1
fi

echo "Новая версия успешно загружена: $(ls -lh ${binary} | awk '{print $5}')"

# Создаем init.d скрипт, если его нет
if [ ! -f "${init_script}" ]; then
    echo "Создаем init.d скрипт..."
    cat << EOF > ${init_script}
#!/bin/sh /etc/rc.common
# Скрипт запуска Torrent сервера

START=95
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command ${binary} -d ${dir} -p 8090 --logpath /tmp/log/torrserver/torrserver.log
    procd_set_param respawn
    procd_close_instance
}
EOF
    chmod +x ${init_script}
    ${init_script} enable
fi

# Запускаем службу
echo "Запускаем службу..."
${init_script} start

# Проверяем версию
new_version=$(${binary} --version 2>/dev/null | head -n1 | sed 's/^TorrServer //')
echo "Установлена версия: ${new_version}"
echo "TorrServer доступен по адресу: http://ваш-ip-роутера:8090"
echo "Готово!"
