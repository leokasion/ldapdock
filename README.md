# ldapdock
*_a configurable container running openLDAP_*

Step by step approach on how to setup and run the openLDAP server on a classic systemd-less Docker image container

_note about the dockerfile and running the generated image container on FG (foreground) or BG (background): by default the dockerfile generates an image to be run in FG, it expects to be run into it and launch slapd (openLDAP server) manually; to run the image container in BG and start slapd automatically without any user intervention, uncomment the line number 31 of the dockerfile._

## _Creating the ldapdock image container_

build ldapdock
```
> sudo docker build --build-arg LDAP_HOST=example.com -t ldapdock .
```

after build, check the docker image has been created properly with the given REPOSITORY name
```
> docker images
REPOSITORY    TAG       IMAGE ID       CREATED       SIZE
ldapdock      latest    0e4a1521b346   6 hours ago   138MB
```

If you just want to jump in the container and right now don't care saving the configuration or directories, you can run it with this command:
```
> docker run -h ${LDAP_HOST:-example.com} -i -p 389:389 -p 639:639 -t ldapdock
```
If you wish (and it is recommended in development) to save the configuration and LDAP directory structure (also called LDAP database) outside of the container, run this command instead:
```
> sudo docker run -i -t -p 389:389 -p 636:636 -h ${LDAP_HOST:-example.com} -v ldap_data:/var/lib/ldap -v ldap_config:/etc/ldap/slapd.d -v ldap_certs:/etc/ldap/certs -v $(pwd)/hosts-certs:/export-certs ldapdock
```
`Parameters explanation:`with -h we are specifying the name of the host, we are using example.com, this is very important. -i tells docker to run in an interactive way instead of running the container in the background. -t goes in hand with -i, and allocates a tty (terminal) so we can run commands. The parameter -p tells Docker it's the port our server will use. -v mounts a volume to save miscellaneous data in general, and config, content such as directories, databases and users.

## _Explaining DN, parentDN, CN, and DC_

One of the key configuration of LDAP is our "DC" or "parent DN" and other terms, which to explain it in a pure pragmatic way, we will use some examples: we use per defect example.com as our domain, so the DC (Distinguished Name) that we would use it is **"dc=example,dc=com"**, instead, if our domain would be for example "ideas.lab.com", the parent DN would be "dc=ideas,dc=lab,dc=com". This configuration it's very often passed with the CN (Common Name) in concatenation with the DN (Distinguished Name), and the result it's very simple, in the case of the domain example.com, it is **DN: "cn=config,dn=example,dn=com"**, or for ideas.lab.com DN: "cn=config,dn=ideas,dn=lab,dn=com". 

## _Inside the ldapdock image container_

Use the following command to start openLDAP
```
root@example:/# slapd -h "ldap:/// ldapi:///" -g openldap -u openldap -F /etc/ldap/slapd.d
```

It's always a good idea to test connectivity to slapd the first times
```
root@example:/# ldapsearch -x -H ldap://localhost -b "dc=example,dc=com" -s base "(objectclass=*)"
# extended LDIF
#
# LDAPv3
# base <dc=example,dc=com> with scope baseObject
...
```

## _Create an Administrator account_

In order to create users with different attributes and permits, we need to create a new admin account besides the root one that comes with slapd by default.\
We will refer to the LDAP Administrator account as **admin or administrative account**, and to the **root account** simply the one sat by default.
When running any <ins>*Administrative task*</ins> that requires the usage of either the admin or root account, like creating an Organizational Unit (ou) or a new user, both accounts will have set the same privileges, meaning both will work, but <ins>*it is strongly recommended to use the admin or administrative one created here.*</ins> An easy way to differentiate them it's setting different passwords for each one, as we will see...

<!--**`why is this needed?`** unnecesary long explanation: in openLDAP, by default a special administrative account is created as core base to execute first hand tasks, however aside being able to bypass ACLs (Access Control Lists), and therefore any other account created, being allowed to authenthicate for operations like ldapadd, ldapmodify and ldapsearch, etc. it has not an actual entry in the dc=example,dc=com tree (our parentDN). This account it is only configured as olcRootDN in the core base directory/database, cn=config (/etc/ldap/slapd.d/'cn=config') and nothing more. It does not create the corresponding entry in any data tree, therefore the server cannot locate the full entry cn=admin,dc=example,dc=com because it does not exists. In pragmatic terms, we need to create an administrative account for our DN and our parentDN, the later being our domain name as previously explained. 
tl;dr cn=admin,dc=example,dc=com is only a rootDN and not a admin data entry directory which is what we need to setup Access Control Lists (ACLs) as well as setup password schemas.-->

Generate a password hash for our administrator user, 1234 here being the password
```
root@example:/# slappasswd -s 1234
{SSHA}yxIgYTzcuRRdlesjfWkIN6K97/8jOrZF
```
Create the .ldif file that will create the admin user, editing the _userPassword_ attribute with our password hash
```
root@example:/# vim create_admin.ldif
dn: cn=admin,dc=example,dc=com
changetype: add
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: admin
userPassword: {SSHA}yxIgYTzcuRRdlesjfWkIN6K97/8jOrZF  # Replace with the hash of your password
description: LDAP administrator
```
Execute create_admin.ldif using the root password (which is the default container's: _admin_)
```
root@example:/etc/ldap# ldapadd -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w admin -f create_admin.ldif
adding new entry "cn=admin,dc=example,dc=com"
```
Check the attributes of our new administrator user of our domain (parentDN)
```
root@example:/# ldapsearch -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -b "cn=admin,dc=example,dc=com" "(objectclass=*)"
# extended LDIF
#
# LDAPv3
# base <cn=admin,dc=example,dc=com> with scope subtree
# filter: (objectclass=*)
# requesting: ALL
#
# admin, example.com
dn: cn=admin,dc=example,dc=com
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: admin
userPassword:: e1NTSEF9eXhJZ1lUemN1UlJkbGVzamZXa0lONks5Ny84ak9yWkY=
description: LDAP administrator
...
```
That's all, our administrator user was properly done.

## _First administrative tasks_

### <ins>_Create our first Organizational Unit (ou) with a new user_</ins>

Prepare a new LDAP directory (ou) called Supergirls with the following data
```
root@example:/# vim add_ou.ldif
dn: ou=Supergirls,dc=example,dc=com
objectClass: organizationalUnit
ou: Supergirls
```

Execute the .ldif file to create it in the LDAP server, and when asked for the **root password**, remember in the dockerfile by default is _admin_
```
root@example:/# ldapadd -x -D "cn=admin,dc=example,dc=com" -W -f add_ou.ldif
Enter LDAP Password:
adding new entry "ou=Supergirls,dc=example,dc=com"
```

verify the entry in the LDAP server
```
root@example:/# ldapsearch -x -LLL -b "dc=example,dc=com" "(ou=Supergirls)" dn
dn: ou=Supergirls,dc=example,dc=com
```

create a new LDAP password to manage our new directory, annotate both the entered _plain password_ and the result _hashed password_
```
root@example:/# slappasswd
New password:
Re-enter new password:
{SSHA}hashedpasswd
```

create a .ldif file with the necessary attributes to insert in our Supergirls directory
```
root@example:/# vim add_user_supergirls.ldif
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
userPassword: {SSHA}hashedpasswd
mail: marisa@example.com
```

insert the new user (marisa) in our Supergirls directory (LDAP OU), still using the root password _admin_
```
root@example:/# ldapadd -x -D "cn=admin,dc=example,dc=com" -W -f add_user_supergirls.ldif
Enter LDAP Password:
adding new entry "uid=marisa,ou=Supergirls,dc=example,dc=com"
```

verify the user (marisa) has been added to the Supergirls OU
```
root@example:/# ldapsearch -x -LLL -b "dc=example,dc=com" "(uid=marisa)" dn
dn: uid=marisa,ou=Supergirls,dc=example,dc=com
```

### <ins>_Modify users attributes_</ins>

create a new .ldif file with the attributes we want to change\
in this case we want to modify the _mail_ marisa@example.com of the user (_uid_) marisa from the group (_ou_) Supergirls
```
root@example:/home# vim modify_user.ldif
dn: uid=marisa,ou=Supergirls,dc=example,dc=com
changetype: modify
replace: mail
mail: marisa.kirisame@example.com
```

run the modify file, when asked for the root password, remember in the dockerfile by default is _admin_
```
root@example:/home# ldapmodify -x -D "cn=admin,dc=example,dc=com" -W -f modify_user.ldif
Enter LDAP Password:
modifying entry "uid=marisa,ou=Supergirls,dc=example,dc=com"
```

verify the _mail_ attribute of the user marisa has been changed to marisa.kirisame@example.com
```
root@example:/home# ldapsearch -x -LLL -b "dc=example,dc=com" "(uid=marisa)" mail
dn: uid=marisa,ou=Engineering,dc=example,dc=com
mail: marisa.kirisame@example.com
```

<!--### <ins>_Modify user password_</ins>

In this examples, we are changing the special attribute password of the user marisa from ou Supergirls, using the old password.\
\
In order to change the password interactively (writing in the prompt when asked), we can run this command:
```
root@example:/etc/ldap# ldappasswd -H ldap:/// -x -D "uid=marisa,ou=Supergirls,dc=example,dc=com" -W -S "uid=marisa,ou=Supergirls,dc=example,dc=com"
New password: newpasswd
Re-enter new password: newpasswd
Enter LDAP Password: oldpasswd
```
_newpasswd_ being the new password we want to use, and _oldpasswd_, the last password we were using for the user uid marisa.\
\
To change the password in an non interactive (sending the password directly via the command), we can run this:
```
root@example:/etc/ldap# ldappasswd -H ldap:/// -x -D "uid=marisa,ou=Supergirls,dc=example,dc=com" -w newpasswd "uid=marisa,ou=Supergirls,dc=example,dc=com"
New password: 6vUj/2lE
```
_newpasswd_ being the new password we want to use. We can also notice the hashed output of our new password is not a typical LDAP SSHA hash, this is due to security implementations.
-->
### <ins>_Reset user password_</ins>

In the likely common event that we forgot the old password of an specific user, we need to reset it.\
In this example we forgot the password of the user uid marisa, we can reset it with this command:
```
root@example:/# ldappasswd -H ldap:/// -x -D "cn=admin,dc=example,dc=com" -W -S "uid=marisa,ou=Supergirls,dc=example,dc=com"
New password: newpasswd
Re-enter new password: newpasswd
Enter LDAP Password: admin
```
Note we need to use the **root** password (_admin_ by default) in the last query ("Enter LDAP Password") to reset an user's password.
\
If we want to change the password as the user marisa, we need to use the user's _plain password_ we entered when we created it:
```
root@example:/# ldappasswd -H ldap:/// -x -D "uid=marisa,ou=Supergirls,dc=example,dc=com" -w _plain password_ -s newpassword "uid=marisa,ou=Supergirls,dc=example,dc=com"
```
With this commmand we changed the user marisa password's from _plain password_ to literally "newpassword", change this as needed.\
`Note we first changed the password interactively (being prompted) using the -W parameter, and later used -w to change it non interactively.`

### <ins>_Query as an specific user_</ins>

we already created the user (_uid_) marisa, and established the user's own password using slappasswd\
now we are gonna query our LDAP server using the user (_uid_) marisa credentials, and _the password we entered during slappasswd, called plain password (plainpasswd)_ 
```
root@example:/# ldapsearch -D uid=marisa,ou=Supergirls,dc=example,dc=com -b "dc=example,dc=com" -w plainpasswd
# extended LDIF
#
# LDAPv3
# base <dc=example,dc=com> with scope subtree
# filter: (objectclass=*)
# requesting: ALL
#

# example.com
dn: dc=example,dc=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: nodomain
dc: example

# Supergirls, example.com
dn: ou=Supergirls,dc=example,dc=com
...
```

we can narrow this search to get only specific attributes of the user marisa, remember we are using _the plainpasswd when asked_
```
root@example:/# ldapsearch -D uid=marisa,ou=Supergirls,dc=example,dc=com -b "dc=example,dc=com" -w plainpasswd givenName uidNumber gidNumber homeDirectory
# extended LDIF
#
# LDAPv3
# base <dc=example,dc=com> with scope subtree
# filter: (objectclass=*)
# requesting: givenName uidNumber gidNumber homeDirectory
#

# example.com
dn: dc=example,dc=com

# Supergirls, example.com
dn: ou=Supergirls,dc=example,dc=com

# marisa, Supergirls, example.com
dn: uid=marisa,ou=Supergirls,dc=example,dc=com
givenName: Marisa
uidNumber: 1001
gidNumber: 5000
homeDirectory: /home/marisa
```
<!--
### <ins>_Reset root password_</ins>

Build line by line, the **.ldif** file we will need to reset root password, starting with the following command:
```
root@example:/# ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config '(olcSuffix=dc=example,dc=com)' dn > rootpw.ldif
```
which writes to the rootpw.ldif file, the current rootDN (Distinguised Name): `dn: olcDatabase={1}mdb,cn=config`\
The next command will add the 'changetype' (modify, add, etc.) and what object are we working with:
```
root@example:/# echo -e 'changetype: modify\nreplace: olcRootPW: ' >> rootpw.ldif
root@example:/etc/ldap# cat rootpw.ldif
dn: olcDatabase={1}mdb,cn=config

changetype: modify
replace: olcRootPW
```
We run a simple sed command to delete blank lines
```
root@example:/# sed '/^$/d' rootpw.ldif > chrootpw.ldif
root@example:/# cat chrootpw.ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
```
It's time to write our new password (_newpasswd_):
```
root@example:/# slappasswd -s 1234
{SSHA}2xbd33S4ZumAZW4Oks0GJidBFJYEVBPz
```
The last line it's our password 1234 hashed in SSHA cryptography. We will need to copy and paste it in the following command:
```
root@example:/# echo "olcRootPW: {SSHA}2xbd33S4ZumAZW4Oks0GJidBFJYEVBPz" >> chrootpw.ldif
```
The file that describes the variables needed to change our root password, **chrootpw.ldif** should be ready, we finally run:
```
root@example:/etc/ldap# ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f chrootpw.ldif
modifying entry "olcDatabase={1}mdb,cn=config"
```
If successful, the output will show the modified entry.
-->

## _Loading and enabling modules_

Since no policy overlays are loaded in slapd in the container, we need to load our own.
\
In the next command, notice we are using the -Q and -Y EXTERNAL -H ldap**i**:///, meaning SASL EXTERNAL authentication over the -x -H ldap:/// socket, which we usually use for binding as the root account. Using -Q -Y EXTERNAL -H ldap**i**:/// works because it binds as the openldap user and has sufficient permissions for cn=config.
Run the following command to query our loaded modules list
```
root@example:/# ldapsearch -Q -Y EXTERNAL -H ldapi:/// -D "cn=admin,dc=example,dc=com" -b cn=config "(objectclass=olcModuleList)"
# extended LDIF
#
# LDAPv3
# base <cn=config> with scope subtree
# filter: (objectclass=olcModuleList)
# requesting: ALL
#
# module{0}, config
dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModulePath: /usr/lib/ldap
olcModuleLoad: {0}back_mdb

```
Reading the output in detail, means we are only loading the default backend (olcModuleLoad: {0}back_mdb) that comes by default with LDAP to load basic schemas such as directories (OU) creation.

Run the following command:
```
root@example:/# ls /usr/lib/ldap/ppolicy*
/usr/lib/ldap/ppolicy-2.5.so.0  /usr/lib/ldap/ppolicy-2.5.so.0.1.14  /usr/lib/ldap/ppolicy.la  /usr/lib/ldap/ppolicy.so
```
Our LDAP server may not come loaded with the policies we need to apply features such as passwords schemas and ACLs (Access Control Lists), but the modules exists inside the container image.
We need to make use of new schemas and **policies**, which in large part exists in /usr/lib/ppolicy.so -since the module exists, we are going to create modify_ppolicy_module.ldif to be able to make use of it:
```
root@example:/# vim modify_ppolicy_module.ldif
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: ppolicy.so
```
Run modify_ppolicy_module.ldif
```
root@example:/# ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f modify_ppolicy_module.ldif
modifying entry "cn=module{0},cn=config"
```
Now we run the exact same command as before to check if the policy overlay was loaded
```
 root@example:/# ldapsearch -Q -Y EXTERNAL -H ldapi:/// -D "cn=admin,dc=example,dc=com" -b cn=config "(objectclass=olcModuleList)"
# extended LDIF
#
# LDAPv3
# base <cn=config> with scope subtree
# filter: (objectclass=olcModuleList)
# requesting: ALL
#

# module{0}, config
dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModulePath: /usr/lib/ldap
olcModuleLoad: {0}back_mdb
olcModuleLoad: {1}ppolicy.so

```
Notice the addition of **olcModuleLoad: {1}ppolicy.so**. If we get a different result from the last command, we won't be able to enable the schemas or ACLs we need, and should check that we did input the right commands to reach this point, from the commands to run the container, if we started slapd with the right parameters, to the correct creation of the user administrator.

To enable our new schemas and policies, that is, to load our new module ppolicy.so in our openLDAP server, we need to restart it, we are going to do it manually (using grep it's optional):
```
root@example:/# kill $(pidof slapd)
root@example:/# ps ax | grep slap
     30 pts/0    S+     0:00 grep --color=auto slap
root@example:/# slapd -h "ldap:/// ldapi:///" -g openldap -u openldap -F /etc/ldap/slapd.d
root@example:/# ps ax | grep slap
     32 ?        Ssl    0:00 slapd -h ldap:/// ldapi:/// -g openldap -u openldap -F /etc/ldap/slapd.d
     36 pts/0    S+     0:00 grep --color=auto slap
```

Now that we restarted our openLDAP server, we can load the new module, so we create the following .ldif file:
```
root@example:/# vim enable_ppolicy.ldif
dn: olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: ppolicy
olcPPolicyDefault: cn=default,ou=policies,dc=example,dc=com
```
We load the module
```
root@example:/# ldapadd -Q -Y EXTERNAL -H ldapi:/// -f enable_ppolicy.ldif
adding new entry "olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config"
```
And then verify it is enabled
```
root@example:/# ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config "(objectclass=olcOverlayConfig)"
dn: olcOverlay={0}ppolicy,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: {0}ppolicy
olcPPolicyDefault: cn=default,ou=policies,dc=example,dc=com
```
If the same output was returned, we are done with creating and loading the policies module, and we can begin creating .ldif with our schemas.

## _Setting up passwords policies, schemas, and ACLs_

First of all, update our openLDAP ACL (Acess Control List) so we can have SASL EXTERNAL perms for the Linux openLDAP user, "openldap", so it can enforce all the following rules we are going to create.
Create the file update_acl.ldif with the following content:
```
root@example:/# vim update_acl.ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword,pwdPolicySubentry by self write by anonymous auth by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" write by * none
olcAccess: {1}to * by dn.exact="cn=admin,dc=example,dc=com" manage by * read
```
This probably looks confusing and even scary now, but it's pretty simple, it basically adds the pwdPolicySubentry attribute to the attributes SASL EXTERNAL can write. We will come back to it later anyways.

```
root@example:/# ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f update_acl.ldif
```

Generate a new password hash like this:
```
root@example:/# slappasswd -s ying
{SSHA}LcyDtEjMaPCBcYgkumVPDBFjliOjJrMC
```

Create a new basic LDAP directory with the Organizational Unit (ou) Supergirls and add the LDAP user (uid) reimu with our previously generated hashed password
```
root@example:/# vim create_reimu.ldif
dn: ou=Supergirls,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: Supergirls

dn: uid=reimu,ou=Supergirls,dc=example,dc=com
changetype: add
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
uid: reimu
cn: Reimu Hakurei
sn: Hakurei
userPassword: {SSHA}LcyDtEjMaPCBcYgkumVPDBFjliOjJrMC
```
This creates our Supergirls directory, and with it the user reimu.

### <ins>_Blocking user access after 3 wrong tries_</ins>

Let's apply the following policy on the user reimu from the Organizational Unit Supergirls: after failing to interact in any way with the LDAP server using the user's wrong password, the LDAP server with block the user and it will disabled of any action until an administrator unlocks it. 
```
root@example:/# vim apply_policy_reimu.ldif
dn: uid=reimu,ou=Supergirls,dc=example,dc=com
changetype: modify
add: pwdPolicySubentry
pwdPolicySubentry: cn=default,ou=policies,dc=example,dc=com
```
And execute the apply_policy_reimu.ldif file
```
root@example:/# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f apply_policy_reimu.ldif
modifying entry "uid=reimu,ou=Supergirls,dc=example,dc=com"
```
Run again the following command taking note of the new hashed passwords
```
root@example:/# slappasswd -s ying
{SSHA}q0/43n3/uhkmMC2hH9gIGUBqmjWRQHjv
```
Finally, create a new file reset_reimu_password.ldif and replace the userPassword with the correct hashed password 
```
root@example:/# vim reset_reimu_password.ldif
dn: uid=reimu,ou=Supergirls,dc=example,dc=com
changetype: modify
replace: userPassword
userPassword: {SSHA}q0/43n3/uhkmMC2hH9gIGUBqmjWRQHjv
```
Execute reset_reimu_password.ldif
```
root@example:/# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f reset_reimu_password.ldif
modifying entry "uid=reimu,ou=Supergirls,dc=example,dc=com"
```
\
First we could test try to change the password of reimu using reimu's password correctly:
```
root@example:/# ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w ying -s yang "uid=reimu,ou=Supergirls,dc=example,dc=com"
```
If we receive no output, the password change was successful. User's reimu's old password was _ying_ and now the new password is _yang_.<!--Let's check the pwdFailureTime and pwdAccountLockedTime-->
Now let's try changing the password, but with a wrong password. Using the same command as before should be enough since we are trying to run a command as user reimu using the old password _ying_ when we just changed to _yang_.
```
root@example:/# ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w ying -s yang "uid=reimu,ou=Supergirls,dc=example,dc=com"
ldap_bind: Invalid credentials (49)
```
Before get the user blocked, let's try once again using the correct password, which is the new one _yang_:
```
root@example:/# ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w yang -s ying "uid=reimu,ou=S
upergirls,dc=example,dc=com"
```
As we see, we are getting no error, since the correct new password was _yang_ and we changed it back to _ying_ as it was from the beginning.

Now, if we use the same command 3 times in a row (3 wrong passwords in a row), as established by policy, the user will get blocked:
```
root@example:/# ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w ying -s yang "uid=reimu,ou=Supergirls,dc=example,dc=com"
ldap_bind: Invalid credentials (49)
root@example:/# ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w ying -s yang "uid=reimu,ou=Supergirls,dc=example,dc=com"
ldap_bind: Invalid credentials (49)
root@example:/# ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w ying -s yang "uid=reimu,ou=Supergirls,dc=example,dc=com"
ldap_bind: Invalid credentials (49)
```
Let's checkout as administrator if the user has some pwd* attributes...
```
root@example:/# ldapsearch -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -b "uid=reimu,ou=Supergirls,dc=example,dc=com" "(objectclass=*)" pwdFailureTime pwdAccountLockedTime
# extended LDIF
#
# LDAPv3
# base <uid=reimu,ou=Supergirls,dc=example,dc=com> with scope subtree
# filter: (objectclass=*)
# requesting: pwdFailureTime pwdAccountLockedTime
#

# reimu, Supergirls, example.com
dn: uid=reimu,ou=Supergirls,dc=example,dc=com
pwdFailureTime: 20251002131513.454814Z
pwdFailureTime: 20251002131955.545595Z
pwdFailureTime: 20251002133529.173964Z
pwdAccountLockedTime: 20251002133529Z
```
The user has been locked out. It cannot do anything using it's user and password.
If we want to unlock it, to give it a clean slate, create the following file
```
root@example:/# vim unlock_reimu.ldif
dn: uid=reimu,ou=Supergirls,dc=example,dc=com
changetype: modify
delete: pwdAccountLockedTime
```
Execute the file to unlock the user
```
root@example:/# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f unlock_reimu.ldif
modifying entry "uid=reimu,ou=Supergirls,dc=example,dc=com"
```
To understand the pwdFailureTime and pwdAccountLockedTime, before when doing our search we got:\
```
dn: uid=reimu,ou=Supergirls,dc=example,dc=com
pwdFailureTime: 20251002131513.454814Z
pwdFailureTime: 20251002131955.545595Z
pwdFailureTime: 20251002133529.173964Z
pwdAccountLockedTime: 20251002133529Z
```
after running unlock_reimu.ldif, we get:
```
dn: uid=reimu,ou=Supergirls,dc=example,dc=com
```
Let's explain how this password lockout system works in a pragmatic way: reimu it's an user which has attributes (like givenName, displayName, mail, etc.), pwdFailureTime and pwdAccountLockedTime are just attributes too, **except they exist dynamically** by the ppolicy.so module which we previously loaded, and is the one that tracks and enforces schemas and policies.

### <ins>_Setting the blocked time_</ins>

To setup the time a user gets blocked out by any reason (such as entering the wrong password several times like before), we have can create the following file:
```
root@example:/# vim update_locktime_policy.ldif
dn: cn=default,ou=policies,dc=example,dc=com
changetype: modify
replace: pwdLockoutDuration
pwdLockoutDuration: 0
```
pwdLockoutDuration being the ket attribute that sets how much **seconds** the lock out will be enforced. Use the following numbers as reference:
pwdLockoutDuration: 0 #indefinitely until an administrator user unlocks the user manually
pwdLockoutDuration: 300 #the user will be locked out for 5 minutes
pwdLockoutDuration: 86400 #the user will be locked out for 24 hours
To enforce the change, run the .ldif file
```
root@example:/# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f update_locktime_policy.ldif
modifying entry "cn=default,ou=policies,dc=example,dc=com"
```
This will apply immediately, meaning that if a user was already locked for 5 minutes **(the default locked out time by openLDAP)**, and we just updated the policy so the lock out would be 0 (indefinitely), when the 5 minutes passes after the user's lock out, the user will be automatically unlocked, the _next time_ it triggers a lock out, the new policy will be enforced, and this time will be locked indefinitely.

### <ins>_Set the max number of retries_</ins>

The max number of wrong password tries before a user is lockd out is controlled by the attribute pwdMaxFailure.\
Create the following set_retries.ldif with the following data:
```
root@example:/# vim update_retries.ldif
dn: cn=default,ou=policies,dc=example,dc=com
changetype: modify
replace: pwdMaxFailure
pwdMaxFailure: 3
```
The variable pwdMaxFailure it's self explainatory.
Now execute the .ldif file
```
root@example:/# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f update_retries.ldif
modifying entry "cn=default,ou=policies,dc=example,dc=com"
```
The new policy will take effect immediately.
As a reminder, we can check out the quantity of times a user has tried to run some command or do some action using the wrong password with the following command:
```
root@example:/# ldapsearch -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -b "uid=reimu,ou=Supergirls,dc=example,dc=com" "(objectclass=*)" pwdFailureTime pwdAccountLockedTime | grep -i -m 100 -A 50 '# requesting: pwdFailureTime pwdAccountLockedTime' | grep -c pwdFailureTime:
2
```
This two commands are a little convoluted but what they're doing is, using ldapsearch and multiple grep, and only showing the number of times the user has entered the wrong password. In this case the user reimu tried to change the password using a wrong password twice.

### <ins>_Setup passwords complexity_</ins>

By default, the minimum password quality policy (pwdPolicyQuality) is: length check of at least 5–6 characters, reject identical characters like aaaaaa or 111111.\
The pwdPolicyQuality can be changed, we will do so later, let's understand how is it enforced for now.\
\
There are different levels of password complexity that comes with the policies module in openLDAP:\
0: No quality checking. Any password is accepted, regardless of complexity. (Default value)\
1: Evaluates the password against its built-in quality checks but does not reject weak passwords. If the password fails (e.g., too short or too simple), it logs a warning but allows the change to proceed.\
2: OpenLDAP strictly enforces password quality, rejecting weak passwords with "Constraint violation" errors and messages like "Password fails quality checking policy".

Setting up passwords complexity level:
```
root@example:/# vim update_policy_quality.ldif
dn: cn=default,ou=policies,dc=example,dc=com
changetype: modify
add: pwdCheckQuality
pwdCheckQuality: 2
```
Execute the update_policy_quality.ldif file...
```
root@example:/# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f update_policy_quality.ldif
modifying entry "cn=default,ou=policies,dc=example,dc=com"
```
While we are setting up the password complexity level, we can learn how to set the password minimum length since it's similar:
```
root@example:/# vim update_policy_minlength.ldif
dn: cn=default,ou=policies,dc=example,dc=com
changetype: modify
replace: pwdMinLength
pwdMinLength: 10
```
The attribute **pwdMinLength** being the password minimum characters.
Now execute the update_policy_minlength.ldif file...
```
root@example:/# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f update_policy_minlength.ldif
modifying entry "cn=default,ou=policies,dc=example,dc=com"
```

<!--We need to specify who we want to apply this new policy (change it from how it was by default before), let's use the user reimu
```
root@example:/# vim apply_policy_reimu.ldif
dn: uid=reimu,ou=Supergirls,dc=example,dc=com
changetype: modify
replace: pwdPolicySubentry
pwdPolicySubentry: cn=default,ou=policies,dc=example,dc=com
```
Execute the .ldif **replacing** the pwdPolicySubentry for the user reimu
```
root@example:/etc/ldap/slapd.d# ldapmodify -x -H ldap:/// -D "cn=admin,dc=example,dc=com" -w 1234 -f apply_policy_reimu.ldif
modifying entry "uid=reimu,ou=Supergirls,dc=example,dc=com"
```
-->
Now let's try changing the password to one too easy, _newreimupass_ being the user's password and _weak_ the newpassword:
```
root@example:/# # ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w newreimupass -s weak "uid=reimu,ou=Supergirls,dc=example,dc=com"
Result: Constraint violation (19)
```
We get an "Constraint violation" error, meaning the new password did not comply with the minimum requirements, and since we setup the pwdPolicyQuality to 2, it got rejected.

Let's try changing the password to one too short, _reimupass_ being the user's password, to  _reimu_ being the newpassword:
```
root@example:/etc/ldap/slapd.d# ldappasswd -x -H ldap:/// -D "uid=reimu,ou=Supergirls,dc=example,dc=com" -w reimupass -s reimu "uid=reimu,ou=Supergirls,dc=example,dc=com"
Result: Constraint violation (19)
```
We get again a "Constraint violation" error, the new password did not comply with the minimum requirements, this time the pwdMinLength being 10 as we defined in update_policy_minlength.ldif.

\
Note that getting a constraint violation while trying to change a password, **does not add a pwdFailureTime attribute entry to the user**, as if we would try to do something with the user, like changing some attribute, using the wrong original password; e.g., getting these errors won't block the user.

### <ins>_Password policy default module's options_</ins>
These are the password policy options that the openLDAP ppolicy.so module accepts by default; more complex ones can be created using .ldif files, as we did in this document, but in general these are more than sufficient.
\
`pwdAttribute` Specifies the attribute the policies who applies to. This is typically userPassword.\
`pwdMinAge` How many seconds must pass between a password change. The default is 0, so the password can be changed at any time.\
`pwdMaxAge` How long in seconds since the last password change a password is allowed; this is used for password expiration periods. The default is passwords never expire.\
`pwdInHistory` How many old passwords are stored. If a user attempts to set a password to one that is already in their historial, they will receive an error. The default is 0, the user can keep re-using the same password indefinitely.\
`pwdMinLength` Require all passwords to have a minimum length. The default is no minimum length requirement. This option to be ENFORCED, needs _pwdCheckQuality_ to be 1 or 2, even if pwdCheckQuality isn’t set, the length requirement will not be enforced.\
`pwdCheckQuality` This controls how the openLDAP server actually enforces password quality checks.\
 The default, which is 0, is to _not_ check the quality of the password. \
 If it is set to 2, the server always _enforces_ the quality checks; if it is unable to check it due to password policies, the password failure will be logged and _rejected_. \
 If it is set to 1, the server will _always_ accept a password, but it _will check it_ and be logged in the event it's unable to check it due to password policies.\
 `pwdMaxFailure` How many times a user can fail to authenticate before the user becomes locked out. In order for this option to be enforced, the pwdLockout attribute can be set to TRUE or FALSE; by default, any user having this attribute, pwdLockout, becomes locked, meaning that removing this attributes also works as setting it to FALSE. The default is 0 or the user not having the attribute, which means infinite tries/no lock out.\
 `pwdLockout` This must be set to TRUE for the pwdMaxFailure setting to take affect. If it is missing or set to FALSE, pwdMaxFailure is ignored.\
 `pwdLockoutDuration` How many seconds before an account that has been locked out will be automatically unlocked by the server. The default is 0.\
 `pwdMustChange` When this is set to TRUE and an administrator resets a user password, the user is forced to reset it themselves on the first login. The default is FALSE.\
 `pwdPolicySubentry` How to set _which password policy_ to apply to an **overlay**. The value should be the DN of the applicable password policy entry.\
 The default is the _olcPPolicyDefault_ attribute of the configuration entry used to apply the overlay. If _olcPPolicyDefault_ doesn’t exist and this attribute is missing, no policies will be enforced.

 
## _Show Organizational Units, users, and attributes_
### <ins>_Show LDAP server directories with the data_</ins>

ldapcat is an intrinsic LDAP tool that dumps all directories entries, like Linux 'cat' for files, outputting them in readable LDIF and attribute-value format
```
root@example:/# slapcat
```
All the data shown can be understood just by reading the type of attributes and it's values, and filtered in any way using Linux tools as grep. You will likely come back to this command very frequently when checking Organizational Units, their users, their attributes, etc.

