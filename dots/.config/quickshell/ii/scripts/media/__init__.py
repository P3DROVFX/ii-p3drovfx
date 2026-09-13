"""Local-media backend primitives.

The modules in this package deliberately do not import Quickshell.  They are
used by the persistent helper process and can therefore be tested on a private
D-Bus session without touching the user's shell or audio output.
"""

