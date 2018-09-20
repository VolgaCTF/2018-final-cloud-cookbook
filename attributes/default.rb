id = 'volgactf-2018-final-cloud'

default[id]['basedir'] = '/var/themis/finals/other/cloud'
default[id]['git_repository'] = 'volgactf-2018-finals/volgactf-2018-finals-smartoracle-cloud'
default[id]['revision'] = 'master'

default[id]['debug'] = false

default[id]['processes'] = 2
default[id]['port_range_start'] = 11_100

default[id]['autostart'] = false

default[id]['db']['name'] = 'cloud'
default[id]['db']['user'] = 'cloud'
