fx_version 'cerulean'
game 'gta5'

author 'you'
description 'Custom NPWD <-> ND Core bridge - workaround for npwd#1141 (phone number wiped on unload/disconnect)'
version '1.0.0'

server_scripts {
    'server.lua'
}

-- Make sure this resource starts AFTER both, and BEFORE nothing else needs npwd:
dependencies {
    'ND_Core',
    'npwd'
}
