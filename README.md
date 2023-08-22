# StatusEvents

## Overview
StatusEvents is a simple plugin. It provides a mechanism to respond to the character status information Aardwolf provides via GMCP. The status can be one of the following values:

1         At login screen, no player yet
2         Player at MOTD or other login sequence
3         Player fully active and able to receive MUD commands
4         Player AFK
5         Player in note
6         Player in Building/Edit mode
7         Player at paged output prompt
8         Player in combat
9         Player sleeping
11        Player resting or sitting
12        Player running

The plugin can operate in two modes:
    1) It can generate a line from the mud that can be triggered upon using Mushclient's trigger functionality.

    2) It can execute actions stored in the plugin on either the Start or End of an event.

Both modes can be used at the same time. There is an additional synthetic event the plugin provides for PK Combat. PK Combat is treated as an addition to regular combat. For PK Combat, both Combat and PK Combat actions will be fired and triggers generated.

The plugin exposes all the events the game provides and the actions the plugin runs are processed in the same manner as if you typed them into Mushclient yourself. This means that aliases, etc work fine as an action

## Installation
Just throw both StatusEvents.xml and StatusEvents.lua into where you keep your plugins and add StatusEvents.xml via the Mushclient Plugins manager.
