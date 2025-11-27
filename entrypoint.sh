#!/bin/bash
set -e

echo ">>> Iniciando Container Moodle..."

# Defaults
: "${MOODLE_VERSION:=MOODLE_402_STABLE}"
: "${MOODLE_GIT_REPO:=https://github.com/moodle/moodle.git}"
: "${DB_TYPE:=pgsql}"
: "${DB_PORT:=5432}"
: "${MOODLE_LANG:=pt_br}"

# ----------------------------------------------------------------------
# 1. Core do Moodle
# ----------------------------------------------------------------------
if [ ! -f "/var/www/html/version.php" ]; then
    echo ">>> Instalando Core Moodle (${MOODLE_VERSION})..."
    if [ "$(ls -A /var/www/html)" ]; then
        echo "AVISO: Pasta não vazia. Tentando git init/pull..."
        git config --global --add safe.directory /var/www/html
        git init
        git remote add origin "$MOODLE_GIT_REPO" || git remote set-url origin "$MOODLE_GIT_REPO"
        git fetch origin "$MOODLE_VERSION"
        git reset --hard FETCH_HEAD
    else
        git clone --branch "$MOODLE_VERSION" --depth 1 "$MOODLE_GIT_REPO" .
    fi
else
    echo ">>> Atualizando Core Moodle (git pull)..."
    git config --global --add safe.directory /var/www/html
    git fetch origin "$MOODLE_VERSION"
    git reset --hard FETCH_HEAD
fi

chown -R www-data:www-data /var/www/html

# ----------------------------------------------------------------------
# 2. Plugins
# ----------------------------------------------------------------------
PLUGINS_CONTENT=""
if [ ! -z "$MOODLE_PLUGINS_JSON" ] && [ "$MOODLE_PLUGINS_JSON" != "[]" ]; then
    PLUGINS_CONTENT="$MOODLE_PLUGINS_JSON"
elif [ -f "/usr/local/bin/default_plugins.json" ]; then
    PLUGINS_CONTENT=$(cat /usr/local/bin/default_plugins.json)
fi

if [ ! -z "$PLUGINS_CONTENT" ]; then
    echo ">>> Processando plugins..."
    if echo "$PLUGINS_CONTENT" | jq . >/dev/null 2>&1; then
        echo "$PLUGINS_CONTENT" | jq -c '.[]' | while read i; do
            GIT_URL=$(echo "$i" | jq -r '.giturl')
            GIT_BRANCH=$(echo "$i" | jq -r '.branch // empty')
            INSTALL_PATH=$(echo "$i" | jq -r '.installpath')
            FULL_PATH="/var/www/html/$INSTALL_PATH"
            CLONE_ARGS=""
            [ ! -z "$GIT_BRANCH" ] && CLONE_ARGS="--branch $GIT_BRANCH"

            if [ -d "$FULL_PATH" ]; then
                echo "--- Atualizando: $INSTALL_PATH"
                cd "$FULL_PATH" || continue
                git config --global --add safe.directory "$FULL_PATH"
                if [ ! -z "$GIT_BRANCH" ]; then
                    git fetch origin "$GIT_BRANCH" && git checkout "$GIT_BRANCH" && git reset --hard "origin/$GIT_BRANCH"
                else
                    git pull || echo "AVISO: Falha no pull de $INSTALL_PATH"
                fi
            else
                echo "--- Instalando: $INSTALL_PATH"
                # shellcheck disable=SC2086
                git clone $CLONE_ARGS "$GIT_URL" "$FULL_PATH"
            fi
        done
        cd /var/www/html
    fi
fi
chown -R www-data:www-data /var/www/html

if [ ! -f "/var/www/html/config.php" ]; then
    echo ">>> Gerando config.php dinâmico..."

    # Prepara o conteúdo Extra
    EXTRA_CONFIG_CONTENT=""

    if [ ! -z "$MOODLE_EXTRA_PHP" ]; then
        echo ">>> Injetando configurações extras via Variável de Ambiente."
        EXTRA_CONFIG_CONTENT="$MOODLE_EXTRA_PHP"
    elif [ -f "/usr/local/bin/config-extra.php" ]; then
        echo ">>> Injetando configurações extras via Arquivo (config-extra.php)."
        # Remove tag PHP de abertura se a pessoa tiver colocado por engano, para não quebrar o arquivo
        EXTRA_CONFIG_CONTENT=$(cat /usr/local/bin/config-extra.php | sed 's/<?php//g' | sed 's/?>//g')
    fi

    # 1. Escreve o cabeçalho padrão
    cat <<EOF > /var/www/html/config.php
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = getenv('DB_TYPE') ?: 'pgsql';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = getenv('DB_HOST') ?: 'localhost';
\$CFG->dbname    = getenv('DB_NAME') ?: 'moodle';
\$CFG->dbuser    = getenv('DB_USER') ?: 'moodle';
\$CFG->dbpass    = getenv('DB_PASS') ?: '';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array (
  'dbport' => getenv('DB_PORT') ?: '',
  'dbpersist' => 0,
  'dbscent' => 0,
);

\$CFG->wwwroot   = getenv('MOODLE_URL');
\$CFG->dataroot  = '/var/www/moodledata';
\$CFG->admin     = 'admin';
\$CFG->directorypermissions = 0777;

// --- INICIO CONFIGURACAO EXTRA ---
EOF

    # 2. Injeta o conteúdo extra diretamente (Append)
    if [ ! -z "$EXTRA_CONFIG_CONTENT" ]; then
        echo "$EXTRA_CONFIG_CONTENT" >> /var/www/html/config.php
    fi

    # 3. Escreve o rodapé
    cat <<EOF >> /var/www/html/config.php
// --- FIM CONFIGURACAO EXTRA ---

require_once(__DIR__ . '/lib/setup.php');
EOF

    chown www-data:www-data /var/www/html/config.php
    chmod 644 /var/www/html/config.php
    echo ">>> config.php criado e configurado."
fi

# ----------------------------------------------------------------------
# 4. Instalação/Upgrade do Banco
# ----------------------------------------------------------------------
echo ">>> Aguardando Banco ($DB_HOST)..."
until echo > /dev/tcp/$DB_HOST/$DB_PORT; do sleep 3; done 2>/dev/null || true

if sudo -u www-data php admin/cli/install_database.php \
    --lang="$MOODLE_LANG" \
    --adminuser="${MOODLE_ADMIN_USER:-admin}" \
    --adminpass="${MOODLE_ADMIN_PASS:-MoodleAdmin123!}" \
    --adminemail="${MOODLE_ADMIN_EMAIL:-admin@localhost}" \
    --agree-license > /dev/null 2>&1; then

    echo ">>> Instalação do Banco de Dados concluída!"
    sudo -u www-data php admin/cli/cfg.php --name=fullname --set="${MOODLE_SITE_FULLNAME:-Moodle Site}"
    sudo -u www-data php admin/cli/cfg.php --name=shortname --set="${MOODLE_SITE_SHORTNAME:-Moodle}"
else
    echo ">>> Executando Upgrade..."
    sudo -u www-data php admin/cli/upgrade.php --non-interactive
fi

echo ">>> Limpando caches..."
sudo -u www-data php admin/cli/purge_caches.php

# ----------------------------------------------------------------------
# 5. Start
# ----------------------------------------------------------------------
echo ">>> Iniciando Supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf