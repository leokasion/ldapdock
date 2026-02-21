# ldapdock
*_a configurable secure openLDAP based container_*

![ldapdock](/media/output.gif)

![ldapdock](/media/phpldapdock.png)

Step by step approach on how to setup and run an openLDAP server on a systemd-less docker image container

## _1- Creating the ldapdock image container_

build ldapdock from the dockerfile and run into it, creating the proper volumes to save databases data, config data, and certs data

```
> docker build -t ldapdock --build-arg LDAP_HOST=example.com .
```
do a "nuclear clean" of our volumes (dir ldap_certs depends if just docker rebuilt)
```
> sudo rm -rf ldap_data/* ldap_config/* ldap_certs/*
```
```
> docker run -i -t -p 389:389 -p 636:636 -p 80:80 -p 443:443 -h ${LDAP_HOST:-example.com} -v ldap_data:/var/lib/ldap -v ldap_config:/etc/ldap/slapd.d -v ldap_certs:/etc/ldap/certs -v $(pwd)/host-certs:/export-certs ldapdock
```

## _2- Run the openLDAP server and populate a directory_

Use the following command to start openLDAP
```
root@example:/# slapd -h "ldap:/// ldapi:/// ldaps:///" -g openldap -u openldap
```

Create some groups and users to populate a directory
```
root@example:/# cat > add_content.ldif << EOF
dn: ou=People,dc=example,dc=com
objectClass: organizationalUnit
ou: People

dn: ou=Groups,dc=example,dc=com
objectClass: organizationalUnit
ou: Groups

dn: cn=mages,ou=Groups,dc=example,dc=com
objectClass: posixGroup
cn: mages
gidNumber: 5000
memberUid: marisa

dn: uid=marisa,ou=People,dc=example,dc=com
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
gecos: Marisa Kirisame
loginShell: /bin/bash
homeDirectory: /home/marisa
EOF
```
When creating the groups and users, we will be asked the openLDAP root password (default: admin)
```
root@example:/# ldapadd -x -D cn=admin,dc=example,dc=com -W -f add_content.ldif
```
Notice the userPassword is invalid, let's set a proper one
```
root@example:/# ldappasswd -x -D cn=admin,dc=example,dc=com -w admin -s qwerty uid=marisa,ou=people,dc=example,dc=com
```

## _3- Load and enable policies module_

Write the .ldif file and load the ppolicy.so module that comes with Debian libraries
```
root@example:/# cat > modify_ppolicy_module.ldif << 'EOF'
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: ppolicy.so
EOF`
```
```
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f modify_ppolicy_module.ldif
```
Restart slapd to load the module (copy and paste the following as a single line)
```
root@example:/# slapd -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap &
sleep 3
```
Write the .ldif file to setup ppolicy.so on the openLDAP server
```
root@example:/# cat > enable_ppolicy.ldif << 'EOF'
dn: olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: ppolicy
EOF
```
<!--olcPPolicyDefault: cn=default,ou=policies,dc=example,dc=com-->
```
ldapadd -Q -Y EXTERNAL -H ldapi:/// -f enable_ppolicy.ldif
```

<!--
Generate a password hash for our administrator user, Op3nLd4p! here being the password to comply with password policies
```
root@example:/# slappasswd -s Op3nLd4p!
{SSHA}vP1xt9t8+/GmOXmqlH1yNh305+MpUDe+
```
Create the .ldif file that will create the admin user, edit the _userPassword_ attribute with our password hash\
(you can copy & paste the entire command until userPassword, copy your password hash with the mouse, and paste it directly)
```
root@example:/# cat > create_admin.ldif << EOF
dn: cn=admin,dc=example,dc=com
changetype: add
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: admin
description: LDAP administrator
userPassword: {SSHA}vP1xt9t8+/GmOXmqlH1yNh305+MpUDe+  # Replace with the hash of your password
EOF
```
```
root@example:/# ldapadd -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w Op3nLd4p! -f create_admin.ldif
adding new entry "cn=admin,dc=example,dc=com"
```
That's all, our administrator user was properly done.
-->

## _4- Add schemas_

Let's add one of the policy schemas that comes with openLDAP, these files can be found in /etc/ldap/schema/. The pre-installed schemas exists in both converted .ldif files that can be loaded directly, as well native .schema formats which can be converted to .ldif files with the package schema2ldif (not loaded by default in this container) if neccesary.
```
root@example:/# ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/corba.ldif
adding new entry "cn=corba,cn=schema,cn=config"
```
The following schemas will be loaded by default:
```
root@example:/# ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config dn
dn: cn=schema,cn=config

dn: cn={0}core,cn=schema,cn=config

dn: cn={1}cosine,cn=schema,cn=config

dn: cn={2}nis,cn=schema,cn=config

dn: cn={3}inetorgperson,cn=schema,cn=config

dn: cn={4}corba,cn=schema,cn=config
```
<!--## _3- Load and enable policy modules_

We need to make use of new schemas and **policies**, which in large part exists in /usr/lib/ppolicy.so -since the module exists, we are going to create modify_ppolicy_module.ldif to be able to make use of it:
```
root@example:/# cat > modify_ppolicy_module.ldif << EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: ppolicy.so
EOF
``` 
```
root@example:/# ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f modify_ppolicy_module.ldif
modifying entry "cn=module{0},cn=config"
```
Reset slapd (openLDAP server)
```
root@example:/# kill $(pidof slapd)
root@example:/# slapd -h "ldap:/// ldapi:///" -g openldap -u openldap -F /etc/ldap/slapd.d
```
Now that we restarted our openLDAP server, we can load the new module, so we create the following .ldif file:
```
root@example:/# cat > enable_ppolicy.ldif << EOF
dn: olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: ppolicy
olcPPolicyDefault: cn=default,ou=policies,dc=example,dc=com
EOF
```
```
root@example:/# ldapadd -Q -Y EXTERNAL -H ldapi:/// -f enable_ppolicy.ldif
adding new entry "olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config"
```
The policies module has been loaded and we can begin to configure password schemas and ACLs.
-->
<!--
## _4- Configure default password policies_

Create a basic overlay of your password policies:
```
root@example:/# cat > passwd_ppolicy_overlay.ldif << EOF
dn: cn=default,ou=policies,dc=example,dc=com
objectClass: pwdPolicy
objectClass: organizationalRole
cn: default
pwdAttribute: userPassword
pwdMinLength: 8
pwdCheckQuality: 2
EOF
```
```
root@example:/# ldapadd -x -D "cn=admin,dc=example,dc=com" -w Op3nLd4p! -H ldapi:/// -f passwd_ppolicy_overlay.ldif
adding new entry "cn=default,ou=policies,dc=example,dc=com"
```
You can change password policies like pwdMinLength, pwdMaxFailure, pwdMaxAge, etc. and all organizationalUnits (and therefore, their users) will be affected by default using this *default ppolicy overlay*.
Refer to https://git.ozymandias.work/okasion/ldapdock/src/branch/main/README.md#ins_password-policy-default-modules-options_ins for a list of all password policies available by default.

### _<ins>Enforcing password policies example</ins>_
In order to enforce our password configuration we need something to control. This is a short example.
Create an organizationalUnit:
```
root@example:/# cat > create_ou.ldif << EOF
dn: ou=Supergirls,dc=example,dc=com
objectClass: organizationalUnit
ou: Supergirls
EOF
```
```
root@example:/etc/ldap/slapd.d# ldapadd -x -D "cn=admin,dc=example,dc=com" -w Op3nLd4p! -H ldapi:/// -f create_ou.ldif
adding new entry "ou=Supergirls,dc=example,dc=com"
```

Create a password hash for the new user marisa
```
root@example:/# slappasswd -s qwerty
{SSHA}fgEXXr2J08jTVfgyOnkRL2I1JNL4Bp5V
```

Create the new user marisa that will belong to organizationalUnit Supergirls (pay attention to copy the hashed password before EOF)
```
root@example:/# cat > create_user.ldif << EOF
dn: uid=marisa,ou=Supergirls,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
cn: Marisa
sn: Kirisame
givenName: Marisa
displayName: Marisa Kirisame
uid: marisa
uidNumber: 1001
gidNumber: 5000
homeDirectory: /home/marisa
loginShell: /bin/bash
userPassword: {SSHA}fgEXXr2J08jTVfgyOnkRL2I1JNL4Bp5V
mail: marisa@example.com
EOF
```
```
root@example:/etc/ldap/slapd.d# ldapadd -x -D "cn=admin,dc=example,dc=com" -w Op3nLd4p! -H ldapi:/// -f create_user.ldif
adding new entry "uid=marisa,ou=Supergirls,dc=example,dc=com"
```

User marisa and all that are added to Supergirls will respect the password default policies, you can check it out, example:
```
root@example:/# ldappasswd -x -w qwerty -H ldapi:/// -D "uid=marisa,ou=Supergirls,dc=example,dc=com" -s marisakirisame
Result: Constraint violation (19)
Additional info: Password fails quality checking policy
```
Password "marisakirisame" is accepted because we established before pwdMinLength was 8.
```
root@example:/# ldappasswd -x -w qwerty -H ldapi:/// -D "uid=marisa,ou=Supergirls,dc=example,dc=com" -s kirisame
```
"kirisame" is rejected because it's only 8 length characters.
-->
## _5- Configure TLS/SSL certificates_

Create cert directories and generate certificates
```
root@example:/# mkdir -p /etc/ldap/certs
root@example:/# cd /etc/ldap/certs
```
CA key
```
root@example:/etc/ldap/certs# certtool --generate-privkey --bits 4096 --outfile ca-key.pem
```
CA template
```
root@example:/etc/ldap/certs# cat > ca.info <<EOF
cn = Example Company CA
ca
cert_signing_key
expiration_days = 3650
EOF
```
CA certificate
```
root@example:/etc/ldap/certs# certtool --generate-self-signed --load-privkey ca-key.pem --template ca.info --outfile ca-cert.pem
```
\
Now let's generate the key, template, and certificate of the openLDAP server\
Server key
```
root@example:/etc/ldap/certs# certtool --generate-privkey --bits 2048 --outfile ldap01_slapd_key.pem
```
Server template
```
root@example:/etc/ldap/certs# cat > ldap01.info <<EOF
organization = Example Company
cn = ${LDAP_HOST}
tls_www_server
encryption_key
signing_key
expiration_days = 365
EOF
```
Server certificate
```
root@example:/etc/ldap/certs# certtool --generate-certificate \
  --load-privkey ldap01_slapd_key.pem \
  --load-ca-certificate ca-cert.pem \
  --load-ca-privkey ca-key.pem \
  --template ldap01.info \
  --outfile ldap01_slapd_cert.pem
```
\
Last but not least, fix some permissions because certificates are very delicate when checking authorization
```
root@example:/etc/ldap/certs# chgrp openldap ldap01_slapd_key.pem
root@example:/etc/ldap/certs# chmod 640 ldap01_slapd_key.pem
```
\
Bundle our certs (CA and server) into one and set the right perms
```
root@example:/etc/ldap/certs# cat ldap01_slapd_cert.pem ca-cert.pem > ldap01_slapd_cert_full.pem
root@example:/etc/ldap/certs# chown root:openldap ldap01_slapd_cert_full.pem
root@example:/etc/ldap/certs# chmod 640 ldap01_slapd_cert_full.pem
```
\
Restart slapd (copy and paste as a single line)
```
root@example:/etc/ldap/certs# slapd -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap &
sleep 3
```
Re-apply TLS config
```
root@example:/etc/ldap/certs# cat > /tmp/certinfo.ldif <<EOF
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
```
```
root@example:/etc/ldap/certs# ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/certinfo.ldif
```
\
Stop temp, start final with LDAPS
```
root@example:/etc/ldap/certs# pkill slapd
root@example:/etc/ldap/certs# slapd -h "ldap:/// ldaps:/// ldapi:///" -u openldap -g openldap -d 0 &
```

Finally set this ENV variable and make it permanent
```
root@example:/etc/ldap/certs# export LDAPTLS_CACERT=/etc/ldap/certs/ca-cert.pem
root@example:/etc/ldap/certs# echo 'export LDAPTLS_CACERT=/etc/ldap/certs/ca-cert.pem' >> ~/.bashrc
root@example:/etc/ldap/certs# source ~/.bashrc
```
## _6- Connect to OpenLDAP server via StartTLS/SSL_

Vital checks of different levels to test **openLDAP's StartTLS and SSL**:\
1.Check StartTLS and SSL, both should output "anonymous"
```
root@example:/# ldapwhoami -x -ZZ -H ldap://${LDAP_HOST}
anonymous
root@example:/# ldapwhoami -x -H ldaps://${LDAP_HOST}
anonymous
```
\
2.Check direct connection via openssl to confirm certificates are working properly:
```
root@example:/# openssl s_client -connect ${LDAP_HOST}:389 -starttls ldap -servername ${LDAP_HOST} #StartTLS
CONNECTED(00000003)
depth=1 CN = Example Company CA
verify return:1
depth=0 O = Example Company, CN = example.com
verify return:1
...
SSL handshake has read 2977 bytes and written 424 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Server public key is 2048 bit
Secure Renegotiation IS NOT supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)
root@example:/# openssl s_client -connect ${LDAP_HOST}:636 -servername ${LDAP_HOST} #SSL
CONNECTED(00000003)
depth=1 CN = Example Company CA
verify return:1
depth=0 O = Example Company, CN = example.com
verify return:1
...
SSL handshake has read 2963 bytes and written 393 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Server public key is 2048 bit
Secure Renegotiation IS NOT supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)
```
The output of both of these commands should be similar. Also, both will show the openLDAP's server CN (example.com in this case). You can terminate the connection with Ctrl+C.

3.A very important check is to make sure connections as users from the OpenLDAP's tree other than admin works: 
```
root@example:/# ldapwhoami -x -D "uid=marisa,ou=People,dc=example,dc=com" -w MarisaNewPass2025 -H ldap://127.0.0.1 #StartTLS
dn:uid=marisa,ou=People,dc=example,dc=com
root@example:/# ldapwhoami -x -D "uid=marisa,ou=People,dc=example,dc=com" -w MarisaNewPass2025 -H ldap://127.0.0.1 #SSL
dn:uid=marisa,ou=People,dc=example,dc=com 
```

To connect to the server via `STARTTLS`, use port 389, to connect to the server via `SSL`, use port 636, both auth method Simple. 
If asked, accept the certificate as with any certificate, or copy the CA file that resides inside ldapdock from out of the container to our host system certificate trust directory (/usr/local/share/ca-certificates/ works for any Debian based distribution):
```
> sudo docker cp ldapdock:/etc/ldap/certs/ca-cert.pem ./mycacert.crt
> sudo cp mycacert.crt /usr/local/share/ca-certificates/
> sudo update-ca-certificates
```
In both cases, providing -h ${LDAP_HOST}, by default the login "user" and password are:\
As admin:
BIND DN="cn=admin,dc=example,dc=com"\
BIND password=admin
As marisa:
BIND DN="uid=marisa,ou=People,dc=example,dc=com"\
BIND password=MarisaNewPass2025
