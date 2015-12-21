#!/bin/bash

uid=$1

/usr/bin/net ads search -P "(& (objectClass=user) (sAMAccountName=${uid}))" "sshPublicKey" | /bin/grep ssh- | /bin/sed 's/sshPublicKey: //'
