"""
https://launch.sporestack.com
"""

from socket import create_connection
from subprocess import Popen, PIPE

import hug
import jinja2
import sporestack
from falcon import HTTP_403, HTTP_404
from datadog import statsd

DEBUG = True

with open('id_rsa.pub') as ssh_key_file:
    sshkey = ssh_key_file.read()


def debug(message):
    if DEBUG is True:
        print(message)
    return message


def render(template, page={}):
    template = jinja2.Environment(
        loader=jinja2.FileSystemLoader('./')
        ).get_template(template)
    return str(template.render(page=page))


def pulse(metric, gauge=None):
    full_metric = 'launch_sporestack.{}'.format(metric)
    if gauge is None:
        statsd.increment(full_metric)
        debug('Sending stat: {}'.format(full_metric))
    else:
        statsd.gauge(full_metric, gauge)
        debug('Sending stat: {}: {}'.format(full_metric, gauge))


@hug.static('/static')
def static():
    return('static',)


@hug.get('/.well-known/acme-challenge/{challenge}',
         output=hug.output_format.html)
def acmechallenge(challenge):
    """
    Helper for LetsEncrypt SSL.
    """
    pulse('acme-challenge')
    with open('ssl/challenge') as fp:
        return fp.read()


@hug.get('/', output=hug.output_format.html)
def index():
    return render('index.html')


@hug.post('/launch',
          output=hug.output_format.json)
def launch(uuid,
           dcid: hug.types.number,
           days: hug.types.number,
           profile,
           response):
    """
    Launch a SporeStack ndoe with a given profile.
    """
    try:
        settings = sporestack.node_get_launch_profile(profile)
    except:
        response.status = HTTP_403
        return 'Profile doesn\'t exist.'
    osid = settings['osid']
    flavor = settings['flavor']
    startupscript = settings['startupscript']
    postlaunch = settings['postlaunch']
    cloudinit = settings['cloudinit']
    output = {'payment_status': False,
              'creation_status': False,
              'address': None,
              'satoshis': None,
              'stdout': None,
              'stderr': None,
              'return_code': None,
              'description': settings['description'],
              'mimetype': settings['mimetype']}
    # FIXME
    # This is probably the worst thing anyone could do, and I'm doing it.
    # Shameless.
    # So sporestack.node() throws 401 on the creation_status after...
    try:
        node = sporestack.node(days=days,
                               sshkey=sshkey,
                               unique=uuid,
                               osid=osid,
                               dcid=dcid,
                               flavor=flavor,
                               startupscript=startupscript,
                               cloudinit=cloudinit)
        output['payment_status'] = node.payment_status
        output['address'] = node.address
        output['satoshis'] = node.satoshis
        pulse('launch.yuck_try')
    except:
        pulse('launch.yuck_except')
        output['payment_status'] = True
        output['creation_status'] = True
        hostname = uuid + '.node.sporestack.com'
        try:
            socket = create_connection((hostname, 22), timeout=2)
            socket.close()
        except:
            pulse('launch.not_ready')
            return output
        command = ['ssh', '-l', 'root', hostname,
                   '-i', 'id_rsa',
                   '-oStrictHostKeyChecking=no',
                   '-oBatchMode=yes',
                   '-oUserKnownHostsFile=/dev/null']
        process = Popen(command, stdin=PIPE, stderr=PIPE, stdout=PIPE)
        postlaunch = bytes(postlaunch, 'utf-8')
        output['stdout'], output['stderr'] = process.communicate(postlaunch)
        output['return_code'] = process.wait()
        # Delete SSH key. Kinda redundant, hrm.
        command = ['ssh', '-l', 'root', hostname,
                   '-i', 'id_rsa',
                   '-oBatchMode=yes',
                   '-oStrictHostKeyChecking=no',
                   '-oUserKnownHostsFile=/dev/null',
                   'rm /root/.ssh/authorized_keys']
        # FIXME
        # process = Popen(command, stdin=PIPE, stderr=PIPE, stdout=PIPE)
        # process.wait()
        pulse('launch.ready')
    return output
