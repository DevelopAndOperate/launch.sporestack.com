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

progress 'Starting freebsd-update'

sed -i '' '/sleep/d' "$(which freebsd-update)" # Don't sleep.
freebsd-update cron && freebsd-update instal

progress 'Starting pkg upgrade'
pkg upgrade

progress 'Starting pkg install'
pkg install ca_root_nss gdnsd2 pwgen curl python3 git
chmod 700 /root

cd /root

git clone https://github.com/teran-mckinney/redirecthttpd.git

cd redirecthttpd

make install

cd /root

python3 -m ensurepip

pip3 install gunicorn

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
#/etc/rc.local

# progress 'Starting Datadog'
# DD_API_KEY=nope sh -c "$(curl -L https://raw.githubusercontent.com/DataDog/dd-agent/master/packaging/datadog-agent/source/setup_agent.sh)"

progress 'Writing rc.local'
echo '#!/bin/sh
# redirecthttpd only does v6 :-/
sysctl net.inet6.ip6.v6only=0
echo launching redirecthttpd
# This is weird. Does not output anything, but it hangs up ssh if it launches successfully, unless we redirect away?
# Some bug that I should fix.
redirecthttpd > /dev/null 2>&1 &
echo launching gunicorn
cd /root/service; gunicorn  --workers 10 -b 0.0.0.0:443 -b [::]:443 --keyfile=ssl/domain.key --certfile=ssl/chained.pem --ssl-version 5 --ciphers EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH main:__hug_wsgi__ >> /var/log/uwsgi 2>&1 &
echo all done
# FIXME
cd /root/.datadog-agent; bin/agent >> /var/log/datadoge 2>&1 &' > /etc/rc.local
chmod 500 /etc/rc.local

mkdir /root/service
