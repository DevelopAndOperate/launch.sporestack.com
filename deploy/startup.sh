#!/bin/sh

DOMAIN=launch.sporestack.com
HOSTMASTER=noonehome

progress() {
	EPOCH=$(date +%s)
	echo "deploy: $EPOCH: $*" > /dev/console
	echo "deploy: $EPOCH: $*"
}

# This runs at the top of cloud-init. We don't even have SSHD running without
# this.

export ASSUME_ALWAYS_YES=yes

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# pkg isn't installed by default on vultr, but this will bootstrap it
# with the above option of ASSUME_ALWAYS_YES=yes

progress 'Starting pkg upgrade'
pkg upgrade

progress 'Starting pkg install'
pkg install ca_root_nss gdnsd2 pwgen curl python3
chmod 700 /root

python3 -m ensurepip

pip3 install uwsgi

progress 'Resetting root password'
pwgen -s 20 1 | pw user mod root -h 0 -s /bin/sh

IP4=$(ifconfig vtnet0 | grep 'inet ' | awk '{print $2}')
IP6=$(ifconfig vtnet0 | grep inet6 | grep -v 'inet6 fe80' | awk '{print $2}')

echo "\$ORIGIN $DOMAIN.
\$TTL 300

@       SOA     $DOMAIN. $HOSTMASTER.$DOMAIN. (
                1337
                300
                300
                300
                300 )

        NS      $DOMAIN.
        AAAA    $IP6
        A       $IP4
" > /usr/local/etc/gdnsd/zones/$DOMAIN


# We start the dns server down here because DNS being up
# might signal the server as ready, and it really only is
# if at least the content and webserver are there first.
# This is probably overkill.
#FIXME: disable gdnsd port 3506 service, maybe? Or use simpler DNS server.
echo 'gdnsd_enable="YES"' >> /etc/rc.conf
# Doesn't seem to start otherwise.
progress 'Starting gdnsd'
service gdnsd start

echo 'ntpd_enable="YES"' >> /etc/rc.conf
progress 'Starting ntpd'
service ntpd start
# Don't let syslogd listen for security reasons.
echo 'syslogd_flags="-ss"' >> /etc/rc.conf

service syslogd restart


# Let the boot process start rc.local on its own.
/etc/rc.local

# progress 'Starting Datadog'
# DD_API_KEY=nope sh -c "$(curl -L https://raw.githubusercontent.com/DataDog/dd-agent/master/packaging/datadog-agent/source/setup_agent.sh)"

progress 'Writing rc.local'
echo '#!/bin/sh

cd /root/service; /usr/local/bin/uwsgi --http-to-https 0.0.0.0:80 --http-to-https [::]:80 -L -p 12 --limit-post 131072 --master --wsgi-file main.py --callable __hug_wsgi__ --https [::]:443,ssl/chained.pem,ssl/domain.key --https :443,ssl/chained.pem,ssl/domain.key >> /var/log/uwsgi 2>&1 &

# FIXME
cd /root/.datadog-agent; bin/agent >> /var/log/datadoge 2>&1 &' > /etc/rc.local
chmod 500 /etc/rc.local

mkdir /root/service
