#!/bin/sh

set -e

DAYS=7

DCID=1 # New Jersey

# Returns hostname
node=$(sporestack spawn --startupscript deploy/startup.sh --group launch.sporestack.com --dcid $DCID --days $DAYS $1 $2)

echo $node

# sporestack node_info $node --attribute end_of_life | sporestack ssh $node --command 'cat > /end_of_life'

tar -czf - .  | sporestack ssh $node --command 'tar -xzvf - -C /root/service'

sporestack ssh $node --command 'cd /root/service; pip3 install -r requirements.txt'

echo "Installing Datadog agent"

sporestack ssh $node --command "DD_API_KEY=$DD_API_KEY sh -c \"\$(curl -L https://raw.githubusercontent.com/DataDog/dd-agent/master/packaging/datadog-agent/source/setup_agent.sh | sed s/wait/kill\ -9/)\""

sporestack ssh $node --command '/etc/rc.local'

echo "Services are backgrounded. Sleeping for 5 seconds..."

sleep 5

sporestack ssh $node --command '/root/audit.sh'

# We do this last in case this is a 0 day server. Risk of it breaking audit.
# But... we should make sure that graceful suicide is working in some other way.
# 1 hour + at may be 5 minutes delayed. Means TTLs should be 1 hour or less.
echo 'service gdnsd stop' | sporestack ssh $node --command 'at -t $(date -j -f %s '$(($(sporestack node_info $node --attribute end_of_life) - 3900))' +%Y%m%d%H%M)'

echo $node
