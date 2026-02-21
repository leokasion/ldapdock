FROM debian:12

# set container hostname and DN in case we don't set it on the docker build/run command
ARG LDAP_HOST=example.com
ENV LDAP_HOST=${LDAP_HOST}

# set non-interactive TERM for docker
ENV DEBIAN_FRONTEND=noninteractive

#──────────────────────────────────────────────────────────────
# Install ALL necessary packages in a single run for minimal image size
#──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends gnupg lsb-release ca-certificates apt-transport-https software-properties-common wget curl \
# Add the Ondřej Surý PHP repository (modern Debian way)
&& wget -qO- https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php-archive-keyring.gpg \
&& echo "deb [signed-by=/usr/share/keyrings/sury-php-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list \
# Update package lists again to include the new PHP repo
&& apt-get update \
# Install all required packages, using PHP 8.1 from the Surý repo
&& apt-get install -y --no-install-recommends \
apt-utils \
slapd ldap-utils gnutls-bin ssl-cert schema2ldif vim mc \
apache2 \
php8.1 libapache2-mod-php8.1 \
php8.1-ldap php8.1-mbstring php8.1-xml php8.1-curl php8.1-intl \
# Clean up APT caches to keep the image small
&& apt-get clean && rm -rf /var/lib/apt/lists/*

# Enable required Apache modules
RUN a2enmod rewrite headers ssl

# Use mpm_prefork (required for PHP)
RUN a2dismod mpm_event && a2enmod mpm_prefork

# Clean up default Apache site
RUN rm -rf /var/www/html/* && \
    echo "<?php phpinfo(); ?>" > /var/www/html/info.php

# preconfigure slapd installation without using systemd
RUN echo "slapd slapd/password1 password admin" | debconf-set-selections && \
    echo "slapd slapd/password2 password admin" | debconf-set-selections && \
    echo "slapd slapd/domain string example.com" | debconf-set-selections && \
    echo "slapd slapd/no_configuration boolean false" | debconf-set-selections && \
    echo "slapd slapd/purge_database boolean true" | debconf-set-selections && \
    echo "slapd slapd/ldapi_tls boolean false" | debconf-set-selections && \
    echo "slapd slapd/move_old_database boolean true" | debconf-set-selections

# make use of debconf-set-selections
RUN dpkg-reconfigure -f noninteractive slapd

# copy newest entrypoint.sh and run it
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

# open up LDAP StartTLS and SSL ports, and Apache ports
EXPOSE 389
EXPOSE 636
EXPOSE 80
EXPOSE 443

#──────────────────────────────────────────────────────────────
# Create directory for exporting certs to host
RUN mkdir -p /export-certs
#──────────────────────────────────────────────────────────────

# set salvable volumes for LDAP data, configuration, certs
VOLUME ["/var/lib/ldap", "/etc/ldap/slapd.d", "/etc/ldap/certs","/export-certs"]

# set correct permissions for openldap user
#RUN chown -R openldap:openldap /var/lib/ldap /etc/ldap/slapd.d

#──────────────────────────────────────────────────────────────
# ENTRYPOINT ensures this sh file ALWAYS runs first before any CMD or command line instruction
ENTRYPOINT ["./entrypoint.sh"]
#──────────────────────────────────────────────────────────────

# CMD provides the default command (/bin/bash) which is passed as an argument to the ENTRYPOINT script
CMD ["/bin/bash"]
