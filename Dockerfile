ARG PHP_VERSION=8.1
FROM php:${PHP_VERSION}-fpm-bullseye

# Metadados
LABEL maintainer="Seu Nome/Projeto"

# Argumentos e Variáveis de Ambiente Padrão
ENV MOODLE_GIT_REPO="https://github.com/moodle/moodle.git"
ENV MOODLE_VERSION="MOODLE_402_STABLE"
ENV MOODLE_LANG="pt_br"
ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalação de Dependências do Sistema e Extensões PHP
# Incluindo Nginx, Git, Supervisor, JQ (para o JSON), e bibliotecas gráficas/zip/banco
RUN apt-get update && apt-get install -y \
    nginx \
    supervisor \
    cron \
    git \
    unzip \
    jq \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    libpq-dev \
    libonig-dev \
    libxslt1-dev \
    graphviz \
    aspell \
    ghostscript \
    clamav \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        zip \
        soap \
        opcache \
        pdo \
        pdo_pgsql \
        pgsql \
        mysqli \
        pdo_mysql \
        exif \
        bcmath \
        xsl \
        sodium \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Configuração do PHP (Valores recomendados para Moodle)
RUN { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=60'; \
        echo 'opcache.fast_shutdown=1'; \
        echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN { \
        echo 'file_uploads = On'; \
        echo 'memory_limit = 512M'; \
        echo 'upload_max_filesize = 100M'; \
        echo 'post_max_size = 100M'; \
        echo 'max_execution_time = 600'; \
        echo 'max_input_vars = 5000'; \
    } > /usr/local/etc/php/conf.d/moodle-overrides.ini

# 3. Preparação de Diretórios
RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/moodledata \
    && chmod 777 /var/www/moodledata \
    && mkdir -p /var/log/supervisor

# 4. Configuração do Cron do Moodle
RUN echo "*/1 * * * * /usr/local/bin/php /var/www/html/admin/cli/cron.php > /dev/null" > /etc/cron.d/moodle-cron \
    && chmod 0644 /etc/cron.d/moodle-cron \
    && crontab /etc/cron.d/moodle-cron

# 5. Copiar Configurações
COPY nginx.conf /etc/nginx/nginx.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

# Porta Exposta (Nginx interno)
EXPOSE 80

WORKDIR /var/www/html

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]