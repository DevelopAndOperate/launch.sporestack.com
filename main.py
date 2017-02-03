"""
https://launch.sporestack.com
"""

from socket import create_connection
from subprocess import Popen, PIPE

import hug
import sporestack
from falcon import HTTP_403
from datadog import statsd

DEBUG = True

with open('id_rsa.pub') as ssh_key_file:
    sshkey = ssh_key_file.read()


def debug(message):
    if DEBUG is True:
        print(message)
    return message


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
    pulse('static')
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
    pulse('index')
    with open('index.html') as fp:
        return fp.read()


@hug.post('/launch',
          output=hug.output_format.json)
def launch(uuid,
           profile,
           response):
    """
    Launch a SporeStack ndoe with a given profile.
    """
    pulse('launch.hit')
    try:
        settings = sporestack.node_get_launch_profile(profile)
        postlaunch = settings['postlaunch']
        pulse('launch.have_profile')
    except:
        pulse('launch.bad_profile')
        response.status = HTTP_403
        return 'Profile doesn\'t exist.'
    output = {'stdout': None,
              'stderr': None,
              'return_code': None,
              'ready': False}
    hostname = uuid + '.node.sporestack.com'
    pulse('launch.about_to_socket')
    try:
        pulse('launch.tryingsocket')
        socket = create_connection((hostname, 22), timeout=2)
        socket.close()
    except:
        pulse('launch.not_ready')
        return output
    pulse('launch.made_it_past_socket')
    command = ['ssh', '-l', 'root', hostname,
               '-i', 'id_rsa',
               '-oStrictHostKeyChecking=no',
               '-oBatchMode=yes',
               '-oUserKnownHostsFile=/dev/null']
    process = Popen(command, stdin=PIPE, stderr=PIPE, stdout=PIPE)
    postlaunch = bytes(postlaunch, 'utf-8')
    output['stdout'], output['stderr'] = process.communicate(postlaunch)
    output['return_code'] = process.wait()
    pulse('launch.return_code', output['return_code'])
    # Delete SSH key.
    command = ['ssh', '-l', 'root', hostname,
               '-i', 'id_rsa',
               '-oBatchMode=yes',
               '-oStrictHostKeyChecking=no',
               '-oUserKnownHostsFile=/dev/null',
               'rm /root/.ssh/authorized_keys']
    process = Popen(command, stdin=PIPE, stderr=PIPE, stdout=PIPE)
    ssh_key_delete_return_code = process.wait()
    output['ready'] = True
    pulse('launch.ssh_key_delete_return_code', ssh_key_delete_return_code)
    pulse('launch.ready')
    return output
