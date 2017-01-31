#!/bin/sh

DAYS=28

# Returns hostname
node=$(sporestack spawn --startupscript deploy/startup.sh --group launch.sporestack.com --days $DAYS $1 $2)

tar -cvzf - .  | sporestack ssh $node --command 'mkdir /root/service; cd /root/service; tar -xzf -; pip3 install -r requirements.txt; /etc/rc.local'
