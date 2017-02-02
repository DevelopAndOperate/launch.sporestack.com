#!/bin/sh

DAYS=0

# Returns hostname
node=$(sporestack spawn --startupscript deploy/startup.sh --group launch.sporestack.com --days $DAYS $1 $2)

tar -czf - .  | sporestack ssh $node --command 'tar -xzvf - -C /root/service'

sporestack ssh $node --command 'cd /root/service; pip3 install -r requirements.txt'
sporestack ssh $node --command '/etc/rc.local'
