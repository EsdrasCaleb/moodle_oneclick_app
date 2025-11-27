#!/bin/bash
set -e

echo ">>> Iniciando Container Moodle para CapRover..."

# Variáveis padrão se não forem passadas
: "${MOODLE_VERSION:=MOODLE_402_STABLE}"
: "${MOODLE_GIT_REPO:=https://github.com/moodle/moodle.git}"
: "${DB_TYPE:=pgsql}" # ou mysqli
: "${DB_PORT:=5432}"

# ----------------------------------------------------------------------
# 1. Instalação/Atualização do Core do Moodle
# ----------------------------------------------------------------------
if [ ! -f "/var/www/html/version.php" ]; then
    echo ">>> Moodle não encontrado. Clonando versão ${MOODLE_VERSION}..."
    # Se o diretório não estiver vazio (arquivos ocultos), git clone reclama.
    # Usamos uma estratégia segura de limpar ou clonar em temp.
    if [ "$(ls -A /var/www/html)" ]; then
        echo "AVISO: Diretório /var/www/html não está vazio. Tentando git init/pull..."
        git config --global --add safe.directory /var/www/html
        git init
        git remote add origin "$MOODLE_GIT_REPO" || git remote set-url origin "$MOODLE_GIT_REPO"
        git fetch origin "$MOODLE_VERSION"
        git reset --hard FETCH_HEAD
    else
        git clone --branch "$MOODLE_VERSION" --depth 1 "$MOODLE_GIT_REPO" .
    fi
    chown -R www-data:www-data /var/www/html
else
    echo ">>> Moodle detectado. Verificando atualizações de código (git pull)..."
    git config --global --add safe.directory /var/www/html
    git fetch origin "$MOODLE_VERSION"
    git reset --hard FETCH_HEAD
    chown -R www-data:www-data /var/www/html
fi

# ----------------------------------------------------------------------
# 2. Instalação de Plugins via JSON
# ----------------------------------------------------------------------
if [ ! -z "$MOODLE_PLUGINS_JSON" ]; then
    echo ">>> Processando lista de plugins JSON..."

    # Valida JSON
    if ! echo "$MOODLE_PLUGINS_JSON" | jq . >/dev/null 2>&1; then
        echo "ERRO: MOODLE_PLUGINS_JSON inválido."
    else
        # Loop pelo JSON
        echo "$MOODLE_PLUGINS_JSON" | jq -c '.[]' | while read i; do
            GIT_URL=$(echo "$i" | jq -r '.giturl')
            INSTALL_PATH=$(echo "$i" | jq -r '.installpath')

            FULL_PATH="/var/www/html/$INSTALL_PATH"

            if [ -d "$FULL_PATH" ]; then
                echo "--- Atualizando plugin em $INSTALL_PATH..."
                cd "$FULL_PATH" || continue
                git config --global --add safe.directory "$FULL_PATH"
                # Tenta pull, se falhar (ex: diretório existe mas não é git), avisa
                git pull || echo "Falha ao atualizar $INSTALL_PATH (Talvez não seja um repo git?)"
            else
                echo "--- Instalando plugin de $GIT_URL em $INSTALL_PATH..."
                git clone "$GIT_URL" "$FULL_PATH"
            fi
        done
        # Volta para raiz
        cd /var/www/html
    fi
fi

# Garante permissões após plugins
chown -R www-data:www-data /var/www/html

# ----------------------------------------------------------------------
# 3. Instalação ou Upgrade do Banco de Dados
# ----------------------------------------------------------------------
echo ">>> Aguardando banco de dados ($DB_HOST:$DB_PORT)..."
# Loop simples de espera (netcat ou bash puro)
until echo > /dev/tcp/$DB_HOST/$DB_PORT; do sleep 3; done 2>/dev/null || true

if [ ! -f "/var/www/html/config.php" ]; then
    echo ">>> config.php não encontrado. Iniciando instalação CLI..."

    # Tenta descobrir a WWWROOT se não passada
    if [ -z "$MOODLE_URL" ]; then
        # Tenta pegar do CapRover
        echo "ERRO: Variável MOODLE_URL (wwwroot) é obrigatória para instalação."
        exit 1
    fi

    # Executa instalação
    # Nota: Passamos --agree-license e --non-interactive
    sudo -u www-data php admin/cli/install.php \
        --chmod=2777 \
        --lang="$MOODLE_LANG" \
        --wwwroot="$MOODLE_URL" \
        --dataroot="/var/www/moodledata" \
        --dbtype="$DB_TYPE" \
        --dbhost="$DB_HOST" \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASS" \
        --dbport="$DB_PORT" \
        --fullname="${MOODLE_SITE_FULLNAME:-Moodle Site}" \
        --shortname="${MOODLE_SITE_SHORTNAME:-Moodle}" \
        --adminuser="${MOODLE_ADMIN_USER:-admin}" \
        --adminpass="${MOODLE_ADMIN_PASS:-MoodleAdmin123!}" \
        --adminemail="${MOODLE_ADMIN_EMAIL:-admin@localhost}" \
        --agree-license \
        --non-interactive || { echo 'Falha na instalação'; exit 1; }

else
    echo ">>> config.php encontrado. Executando script de upgrade..."

    # Se quiser forçar a atualização da URL caso mude no CapRover,
    # teria que editar o config.php aqui via sed, mas é arriscado.

    # Roda upgrade (não interativo)
    sudo -u www-data php admin/cli/upgrade.php --non-interactive
fi

echo ">>> Limpeza de cache..."
sudo -u www-data php admin/cli/purge_caches.php

# ----------------------------------------------------------------------
# 4. Iniciar Supervisor (Nginx + PHP-FPM + Cron)
# ----------------------------------------------------------------------
echo ">>> Tudo pronto! Iniciando serviços..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf