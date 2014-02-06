---
layout: post
title: "My Precious"
description: "Personal Note Keeping"
modified: 2014-01-18
category: articles
tags : [ruby gollum git nginx ssl]
---

I though I would describe the most recent incarnation of my personal note
keeping system. In the past I have tried a VimWiki in a Git repository,
EverNote, SimpleNote, and then GoogleDocs. But none of them satisfied all my
requirements:

* Markdown text files
* Versioning and backup
* Privacy (encryption)
* Cross platform: Vim, phones, tablets, browsers
* Synchronisation cross platforms

### Enter Gollum

Gollum is a simple markdown Wiki with a Web interface created by the good people
at Github. There are two reasons it is a good choice for me.

1. It is written in Ruby and can be installed as a Gem.

2. It is backed by a Git repository and every edit in the Web interface creates
   a commit.

As you can see Gollum is a self hosted solution, so it is going to require a VPS
(I use Digital Ocean).

### Provisioning

My current go to system for provisioning servers is Ansible. It's primary
mechanism for configuring servers is to issue shell commands over a SSH
connection so there is almost no setup on the server to use it. Admittedly some
of the Ansible modules require Python libraries on the server, but these can be
easily installed by Ansible itself.

Ansible setup scripts, called playbooks, are written in YAML and are
consequently easy to read. So much so I thought I would use them in this post to
document the setup.

The following playbook excerpt creates a user called wiki and copies a local
authorized_keys file to its ssh directory.

~~~ yaml
- name: create user
  user: name=wiki shell=/bin/bash

- name: create ssh dir
  sudo: yes
  sudo_user: wiki
  file:
    path: ~/.ssh
    owner: wiki
    group: wiki
    mode: 0755
    state: directory

- name: authorized keys
  sudo: yes
  sudo_user: wiki
  copy:
    src: authorized_keys
    dest: ~/.ssh/authorized_keys
    owner: wiki
    group: wiki
    mode: 0644
~~~

### Install Gollum

The server already has an up to date Ruby installed system wide. I use Bundler
(the Ruby tool for managing Gem dependencies) to install the Gems. So I copy a
Gemfile to the server and bundle into the wiki users home directory.

~~~ yaml
- name: gollum deps
  apt: name=libicu-dev

- name: Gemfile
  sudo: yes
  sudo_user: wiki
  copy:
    src: Gemfile
    dest: ~/Gemfile owner=wiki

- name: bundle install
  sudo: yes
  sudo_user: wiki
  command: bundle install --binstubs=./bin --path=./bundle chdir=~

- name: bundle update
  sudo: yes
  sudo_user: wiki
  command: bundle update gollum chdir=~
~~~

### Clone the repo

Next thing to do is clone the wiki repository, since I want my notes to remain
private I am using a free private repository on bitbucket. Normally a working
git repo will reject any attempts to push to it for fear of the index and work
tree becoming inconsistent. To avoid this I create a post receive hook script
that will git reset --hard the repo after any push. This is dangerous and could
result in losing changes if one forgets to pull this branch before pushing to
it.

~~~ yaml
- name: repo
  sudo: yes
  sudo_user: wiki
  git:
    repo: ssh://example.com/wiki.git
    dest: ~/repo

- name: allow the working repo to be pushed to
  sudo: yes
  sudo_user: wiki
  command: git config receive.denycurrentbranch ignore chdir=~/repo

- name: git hook script
  sudo: yes
  sudo_user: wiki
  copy: src=post-receive dest=~/repo/.git/hooks/post-receive owner=wiki group=wiki mode=0755
~~~

~~~ bash
#!/bin/sh
git reset --hard
echo "Changes pushed to the repo, I hope you pulled first!"
~~~

### Start Gollum

So now Gollum is installed and the repo is cloned we can start up Gollum. I use
a little restart script.

~~~ bash
#!/usr/bin/env bash
cd $HOME
pkill -u wiki -f ruby.\*bin/gollum
bundle exec gollum repo >~/gollum.log 2>&1 &
~~~

### Nginx

The default port for Gollum is 4567 and it binds to the loop back interface so
it is not yet publicly accessible. Also there is the small issue of security,
since Gollum itself has no form of authentication. I use Nginx to proxy Gollum
to a subdomain I have and I also use Nginx to enforce authentication.

For maximum security I decided to take this opportunity to learn about client
side SSL authentication.

~~~ yaml
- name: vhost
  copy:
    src: wiki
    dest: /etc/nginx/sites-available/wiki
    owner: root
    group: root
    mode: 0644

- name: ssl
  copy:
    src: "{{item}}"
    dest: /etc/ssl/{{item}}
    owner: root
    group: root
    mode: 0400
  with_items:
    - server.crt
    - server.key
    - ca.crt

- name: enable vhost
  file:
    src: /etc/nginx/sites-available/wiki
    dest: /etc/nginx/sites-enabled/wiki
    owner: root
    group: root
    state: link

- name: restart nginx
  command: service nginx reload
~~~

~~~ nginx
# /etc/nginx/sites-available/wiki
server {
  listen 443;
  ssl on;
  ssl_certificate /etc/ssl/server.crt;
  ssl_certificate_key /etc/ssl/server.key;
  ssl_client_certificate /etc/ssl/ca.crt;
  ssl_verify_client on;

  server_name example.com;

  rewrite_log on;

  location / {
    proxy_pass http://localhost:4567/;
    proxy_redirect off;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_set_header X-NginX-Proxy true;
  }
}

server {
  listen 80;
  server_name example.com;
  rewrite ^ https://example.com? permanent;
}
~~~

### SSL

So now we have to generate those key and certificate files. For my own
satisfaction I wanted to understand what was going on. After some reading and
some thinking I came to this understanding. There are three pieces of
information: private key, public key and identity (name, address etc). There are
three participants: CA (certificate authority), the server (nginx) and the
client (browser). These participants each have the three pieces of information.

If we want to securely send a message from one identity to another there are two
things we would like to guarantee. That only the intended recipient identity can
read the message and that the intended recipient identity can confirm the
identity the message came from.

The first guarantee is achieved by encrypting the message with the public key of
the intended recipient. The theory assures us that this message can only be
decrypted with the corresponding private key. So as their names suggest the
private key is kept secret and the public key is published.

The second guarantee is achieved by encrypting some piece of shared data with
the senders private key. The recipient can then decrypt this using the senders
public key thus confirming the senders private key was used to encrypt it.

If the shared data used in the second guarantee is the hash of the message
itself then the integrity of the message can be confirmed as well. In this case
the message is said to be signed.

But how does the recipient know if a public key truly belongs to a particular
identity? This is where certificates come in.  A certificate is a combination of
public key and an identity, signed by a CA private key. The assumption here is
that the recipient trusts the CA.

For our purposes we can play the roles of all three identities. The server the
client and the CA they both trust.

1. Create a private key for the CA

    ~~~ bash
    openssl genrsa -des3 -out ca.key 4096
    ~~~

2. Create a CA certificate for signing both server and client certificate. This
   command will ask for identity information.

    ~~~ bash
    openssl req -new -x509 -days 365 -key ca.key -out ca.crt
    ~~~

3. Create a private key for the server

    ~~~ bash
    openssl genrsa -des3 -out server.key 4096
    ~~~

4. Create a certificate signing request for the server. This command will ask
   for identity information. The CSR is the file given to the CA for
   certification.

    ~~~ bash
    openssl req -new -key server.key -out server.csr
    ~~~

5. Have the CA endorse the CSR and create a certificate for the server.

    ~~~ bash
    openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key -set_serial 01 -out server.crt
    ~~~

6. Now create a private key for the client.

    ~~~ bash
    openssl genrsa -des3 -out client.key 4096
    ~~~

7. Create a CSR for the client.

    ~~~ bash
    openssl req -new -key client.key -out client.csr
    ~~~

8. Have the CA endorse the CSR and create a certificate for the client. I had to
   use a different serial from the server certificate otherwise the PKCS 12 file
   wouldn't import into Firefox.

    ~~~ bash
    openssl x509 -req -days 365 -in client.csr -CA ca.crt -CAkey ca.key -set_serial 02 -out client.crt
    ~~~

9. Create a PKCS 12 file from the client private key and client certificate to
   import into Firefox to access the wiki.

    ~~~ bash
    openssl pkcs12 -export -in client.crt -inkey client.key -out client.p12
    ~~~

10. Finally remove the passphrase from the server private key so Nginx can
    restart unatteneded.

    ~~~ bash
    cp server.key{,.org} && openssl rsa -in server.key.org -out server.key
    ~~~~

Steps 6-9 can be used to create any number of client certificates for multiple
users. It should also be noted that it is good practice, to add passphrases to
the private keys when they are created.

### Web Browser

After the server is configured the last thing to do a install the client key and
certificate into the browser. Firefox has it's own key manager, Safari on OSX
uses the OSX keyring. On OSX chrome should use the OSX keyring as well, but it
doesn't.

### The future

What I would really like is a native iOS app for editing Gollum Wikis using the
Gollum API. Maybe I should write one myself.

### References

- [A tutorial](http://nategood.com/client-side-certificate-authentication-in-ngi)
- [Another tutorial](http://rynop.wordpress.com/2012/11/26/howto-client-side-certificate-auth-with-nginx/)
