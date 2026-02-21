#!/bin/bash
#set -euo pipefail

# Fix permissions
chown -R openldap:openldap /var/lib/ldap /etc/ldap/slapd.d /etc/ldap/certs 2>/dev/null || true
chmod -R 777 /export-certs 2>/dev/null || true

#──────────────────────────────────────────────────────────────
# Correct base DN and hostname
export LDAP_HOST="${LDAP_HOST:-$(hostname)}"
export LDAP_BASE_DN=$(echo "$LDAP_HOST" | sed 's/\.\([^.]*\)/,dc=\1/g; s/^/dc=/')
echo "--> Using LDAP base DN: ${LDAP_BASE_DN}"
#──────────────────────────────────────────────────────────────

echo "--> Starting ldapdock 0.10"

# Temporarily "relax" strict security on start to configure stuff
if [ -d "/etc/ldap/slapd.d" ] && ls /etc/ldap/slapd.d/* >/dev/null 2>&1; then
    echo "--> Temporarily relaxing security for init"
    slapd -h "ldap:/// ldapi:///" -u openldap -g openldap &
    sleep 6
    ldapmodify -Y EXTERNAL -H ldapi:/// >/dev/null 2>&1 <<EOF || true
dn: cn=config
changetype: modify
delete: olcLocalSSF
-
delete: olcSecurity
-
EOF
    pkill slapd || true
    sleep 2
fi

# Start temporary slapd for Users and Groups addition
echo "--> Starting temporary slapd"
slapd -h "ldap:/// ldapi:///" -u openldap -g openldap &
SLAPD_PID=$!
sleep 8

# Full tree with root and users entries
echo "--> Creating base.ldif with root and user entries"  
cat > /tmp/base.ldif <<EOF
dn: ${LDAP_BASE_DN}
objectClass: top
objectClass: dcObject
objectClass: organization
o: Example Company

dn: ou=People,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: People

dn: ou=Groups,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: Groups

dn: cn=mages,ou=Groups,${LDAP_BASE_DN}
objectClass: posixGroup
cn: mages
gidNumber: 5000

dn: uid=marisa,ou=People,${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: marisa
sn: Kirisame
givenName: Marisa
cn: Marisa Kirisame
displayName: Marisa Kirisame
uidNumber: 10000
gidNumber: 5000
userPassword: {CRYPT}x
loginShell: /bin/bash
homeDirectory: /home/marisa
gecos: Marisa Kirisame
EOF

# Create phplogin.php with dynamic base DN
echo "--> Creating phplogin.php with full users support"
cat > /var/www/html/phplogin.php <<'EOF'
<?php
// Use the same logic as entrypoint.sh, but with better localhost handling
$raw_host = $_SERVER['HTTP_HOST'] ?? 'example.com';
$raw_host = preg_replace('/:\d+$/', '', $raw_host); // strip port if present

if ($raw_host === 'localhost' || $raw_host === '127.0.0.1') {
    // When testing locally via http://localhost → assume default example.com
    $base_dn = 'dc=example,dc=com';
} else {
    // Normal case: build dc=... from real hostname
    $host_parts = explode('.', $raw_host);
    $base_dn = '';
    foreach ($host_parts as $part) {
        if ($part) $base_dn .= ($base_dn ? ',' : '') . 'dc=' . $part;
    }
    if (!$base_dn) $base_dn = 'dc=example,dc=com'; // ultimate fallback
}

$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';

    if ($username && $password) {
        $ldap = ldap_connect("ldap://127.0.0.1:389");
        if ($ldap) {
            ldap_set_option($ldap, LDAP_OPT_PROTOCOL_VERSION, 3);
            ldap_set_option($ldap, LDAP_OPT_REFERRALS, 0);

            if (ldap_start_tls($ldap)) {
                // First: try admin bind (no ou=People)
                $admin_dn = "cn=admin,{$base_dn}";
                if (@ldap_bind($ldap, $admin_dn, $password)) {
                    $msg = "<p style='color:green;font-weight:bold'>Login successful! Welcome <strong>admin</strong> (full privileges)</p>";
                }
                // Second: if not admin, try regular user
                elseif (@ldap_bind($ldap, "uid={$username},ou=People,{$base_dn}", $password)) {
                    $msg = "<p style='color:green;font-weight:bold'>Login successful! Welcome {$username}</p>";
                }
                else {
                    $msg = "<p style='color:red'>Invalid credentials</p>";
                }
            } else {
                $msg = "<p style='color:red'>StartTLS failed</p>";
            }
            ldap_close($ldap);
        } else {
            $msg = "<p style='color:red'>Could not connect to LDAP server</p>";
        }
    } else {
        $msg = "<p style='color:red'>Please fill both fields</p>";
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>ldapdock LDAP login</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 400px; margin: 100px auto; text-align: center; }
        input, button { padding: 10px; margin: 5px; width: 100%; font-size: 16px; box-sizing: border-box; }
        button { background: #007cba; color: white; border: none; cursor: pointer; }
        .note { font-size: 0.9em; color: #666; }
    </style>
</head>
<body>
    <h1>ldapdock login</h1>
    <p>Server base DN: <strong><?= htmlspecialchars($base_dn) ?></strong></p>
    <?= $msg ?>
    <form method="post">
        <input type="text" name="username" placeholder="Username (marisa or admin)" required autofocus>
        <input type="password" name="password" placeholder="Password" required>
        <button type="submit">Login</button>
    </form>
    <hr>
    <div class="note">
        <strong>Test accounts:</strong><br>
        Regular user: <code>marisa</code> / password: <code>MarisaNewPass2025</code><br>
        Admin user: <code>admin</code> / password: <code>admin</code>
    </div>
</body>
</html>
EOF

ADMIN_DN="cn=admin,${LDAP_BASE_DN}"
ADMIN_PW="admin"

echo "--> Adding base structure"
ldapadd -c -x -D "$ADMIN_DN" -w "$ADMIN_PW" -f /tmp/base.ldif || true

#──────────────────────────────────────────────────────────────
# TLS BLOCK 
#──────────────────────────────────────────────────────────────
if [ ! -f "/export-certs/mycacert.crt" ]; then
    echo "--> No CA found → generating certificates..."
    mkdir -p /etc/ldap/certs
    cd /etc/ldap/certs
    certtool --generate-privkey --bits 4096 --outfile ca-key.pem
    cat > ca.info <<EOF
cn = Example Company CA
ca
cert_signing_key
expiration_days = 3650
EOF
    certtool --generate-self-signed --load-privkey ca-key.pem --template ca.info --outfile ca-cert.pem
    certtool --generate-privkey --bits 2048 --outfile ldap01_slapd_key.pem
    cat > ldap01.info <<EOF
organization = Example Company
cn = ${LDAP_HOST}
tls_www_server
encryption_key
signing_key
expiration_days = 365
EOF
    certtool --generate-certificate \
      --load-privkey ldap01_slapd_key.pem \
      --load-ca-certificate ca-cert.pem \
      --load-ca-privkey ca-key.pem \
      --template ldap01.info \
      --outfile ldap01_slapd_cert.pem
    chgrp openldap ldap01_slapd_key.pem
    chmod 640 ldap01_slapd_key.pem
    cat ldap01_slapd_cert.pem ca-cert.pem > ldap01_slapd_cert_full.pem
    chown root:openldap ldap01_slapd_cert_full.pem
    chmod 640 ldap01_slapd_cert_full.pem
    echo "--> Starting second temporary slapd to apply TLS config"
    slapd -h "ldap:/// ldapi:///" -u openldap -g openldap &
    sleep 4
    cat > /tmp/certinfo.ldif <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ldap/certs/ca-cert.pem
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/certs/ldap01_slapd_cert_full.pem
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/certs/ldap01_slapd_key.pem
EOF
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/certinfo.ldif
    cp /etc/ldap/certs/ca-cert.pem /usr/local/share/ca-certificates/mycacert.crt
    update-ca-certificates
    pkill slapd || true
    sleep 2
    echo "--> Exporting certificates to host volume..."
    cp /etc/ldap/certs/ca-cert.pem /export-certs/mycacert.crt
    cp /etc/ldap/certs/ldap01_slapd_cert_full.pem /export-certs/server-cert.pem
else
    echo "--> Certificates already exist — skipping generation and using existing ones"
fi

export LDAPTLS_REQCERT=allow

# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
# NEW: Save and restore the LDIF — no changes to TLS block
if [ ! -f "/export-certs/certinfo.ldif" ]; then
    echo "--> Saving TLS config LDIF for future restarts"
    cp /tmp/certinfo.ldif /export-certs/certinfo.ldif
fi

if [ -f "/export-certs/certinfo.ldif" ]; then
    echo "--> Restoring TLS config LDIF from persistent volume"
    cp /export-certs/certinfo.ldif /tmp/certinfo.ldif
fi
# ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←

# Set Marisa password (full LDIF — so ldapmodify knows what to modify)
echo "--> Setting Marisa password to 'MarisaNewPass2025' using Admin Bind"
slappasswd -h '{SSHA}' -s MarisaNewPass2025 | \
ldapmodify -x -D "$ADMIN_DN" -w "$ADMIN_PW" <<EOF >/dev/null 2>&1
dn: uid=marisa,ou=People,${LDAP_BASE_DN}
changetype: modify
replace: userPassword
userPassword: $(< /dev/stdin)
EOF

# Kill temporary slapd
kill $SLAPD_PID 2>/dev/null || true
wait $SLAPD_PID 2>/dev/null || true

# Kill any stray slapd that might be holding ports
pkill -9 slapd 2>/dev/null || true
sleep 2

# Start final OpenLDAP
echo "--> Starting final OpenLDAP (background)"
slapd -h "ldap:/// ldaps:/// ldapi:///" -u openldap -g openldap -d 0 &
SLAPD_PID=$!
sleep 8

# Apply TLS config to final slapd
echo "--> Applying TLS config to final slapd"
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/certinfo.ldif

# Restart slapd to load the new TLS config (required for OpenLDAP)
echo "--> Restarting slapd to load TLS config"
kill $SLAPD_PID 2>/dev/null || true
wait $SLAPD_PID 2>/dev/null || true
slapd -h "ldap:/// ldaps:/// ldapi:///" -u openldap -g openldap -d 0 &
SLAPD_PID=$!
sleep 8

# Make the container trust its own CA — every time
cp /etc/ldap/certs/ca-cert.pem /usr/local/share/ca-certificates/mycacert.crt 2>/dev/null || true
update-ca-certificates --fresh >/dev/null 2>&1 || true

# Start Apache inside APACHE_PID variable in background
echo "--> Starting Apache + PHP (background)"
/usr/sbin/apache2ctl -D FOREGROUND  &
APACHE_PID=$!
sleep 5

# HTTPS setup — using the real LDAP certificates
echo "--> Configuring Apache for HTTPS with real certificates"

export DEBIAN_FRONTEND=noninteractive  # Silence a2ensite prompts

APACHE_CERT_FILE="/etc/ldap/certs/ldap01_slapd_cert_full.pem"
APACHE_KEY_FILE="/etc/ldap/certs/ldap01_slapd_key.pem"

# Enable the site silently
a2ensite default-ssl.conf >/dev/null 2>&1

# Replace the snakeoil certs with your real ones
sed -i -E "s|^\s*SSLCertificateFile\s+.*|SSLCertificateFile ${APACHE_CERT_FILE}|g" \
    /etc/apache2/sites-available/default-ssl.conf
sed -i -E "s|^\s*SSLCertificateKeyFile\s+.*|SSLCertificateKeyFile ${APACHE_KEY_FILE}|g" \
    /etc/apache2/sites-available/default-ssl.conf

# Reload Apache gracefully (updates config without killing)
apache2ctl graceful >/dev/null 2>&1
sleep 5

# ──────────────────────────────
# phpLDAPadmin — auto-installed, no rebuild, works forever
# ──────────────────────────────
echo "--> Installing phpLDAPadmin"

# Only install once — use a flag file
if [ ! -f "/var/www/html/phpldapadmin-installed" ]; then
    cd /var/www/html

    # Download and extract (direct tarball, no git needed)
    wget -q -O phpldapadmin.tgz \
      https://github.com/leenooks/phpLDAPadmin/archive/refs/tags/1.2.6.7.tar.gz
    tar xzf phpldapadmin.tgz
    mv phpLDAPadmin-1.2.6.7 phpldapadmin
    rm phpldapadmin.tgz

    # Copy config and apply minimal working settings
    cp phpldapadmin/config/config.php.example phpldapadmin/config/config.php

cat > phpldapadmin/config/config.php <<EOF
<?php
\$servers = new Datastore();

\$servers->newServer('ldap_pla');
\$servers->setValue('server','name','Local OpenLDAP');
\$servers->setValue('server','host','127.0.0.1');
\$servers->setValue('server','port',389);
\$servers->setValue('server','base',array('${LDAP_BASE_DN}'));
\$servers->setValue('server','tls',true);
\$servers->setValue('login','auth_type','session');
\$servers->setValue('login','bind_id','cn=admin,${LDAP_BASE_DN}');
\$servers->setValue('login','bind_pass','admin');
?>
EOF

    # Mark as installed
    touch /var/www/html/phpldapadmin-installed

    echo "--> phpLDAPadmin installed → https://localhost/phpldapadmin"
else
    echo "--> phpLDAPadmin already installed"
fi

# Victory message
echo "--> ldapdock ready — OpenLDAP + Apache + PHP running"
echo "   → LDAP: 389/636"
echo "   → PHPinfo: https://localhost/info.php"
echo "   → PHPlogin test: https://localhost/phplogin.php"
echo "   → Shell: /bin/bash"
echo "   → Exit with CTRL+D or 'exit' command"

# THIS IS THE MAGIC LINE THAT KILLS CHILD PROCESSES ON EXIT
trap 'echo "Stopping services..."; kill $SLAPD_PID $APACHE_PID 2>/dev/null; wait' SIGINT SIGTERM

# Give you your interactive shell — forever
exec "$@"

