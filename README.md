# TwitchViewerLogger
log/track logged-in twitch users viewing any specific live stream

# DISCLAIMER:
Use at your own risk. this comes with no guarantees/waranty and I am not liable for
anything you do with this script. It is intended for good.

probably against TOS/EULA or something
highly likely this is /abusing/ this endpoint
BUT - this will more than respect the ratelimiting implemented in the API though it
doesnt appear to be present here.

chatters != viewers, viewers can be anon and not included in chat
tracking is not /always/ real time, this style of behavior is already seen
in the twitch chat window itself. offlining is slightly hanlded magically as
it seems android and some PC users flap state back to back polls frequently

probably filled with bugs and will die silently lol

# Usage
ruby tvl.rb --help

combine flags for fun


# Req
Ruby >2
json gem
optparse gem
