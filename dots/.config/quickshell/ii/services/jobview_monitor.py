import sys
import os
import json
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

class JobView(dbus.service.Object):
    def __init__(self, bus, path, app_name, app_icon, capabilities):
        dbus.service.Object.__init__(self, bus, path)
        self.job_id = path.split('/')[-1]
        self.app_name = app_name
        self.app_icon = app_icon
        self.percent = 0
        self.message = ""
        self.speed = 0
        self.processed = 0
        self.total = 0
        self.unit = ""
        self.emit_update("created")

    def emit_update(self, state="running"):
        data = {
            "event": "update",
            "id": self.job_id,
            "appName": self.app_name,
            "appIcon": self.app_icon,
            "state": state,
            "percent": self.percent,
            "message": self.message,
            "speed": self.speed,
            "processed": self.processed,
            "total": self.total,
            "unit": self.unit
        }
        print(json.dumps(data), flush=True)

    @dbus.service.method('org.kde.JobViewV2', in_signature='u')
    @dbus.service.method('org.kde.JobView', in_signature='u')
    def setPercent(self, percent):
        self.percent = int(percent)
        self.emit_update()

    @dbus.service.method('org.kde.JobViewV2', in_signature='s')
    @dbus.service.method('org.kde.JobView', in_signature='s')
    def setInfoMessage(self, message):
        self.message = str(message)
        self.emit_update()

    @dbus.service.method('org.kde.JobViewV2', in_signature='xs')
    @dbus.service.method('org.kde.JobView', in_signature='xs')
    def setProcessedAmount(self, amount, unit):
        self.processed = int(amount)
        self.unit = str(unit)
        self.emit_update()

    @dbus.service.method('org.kde.JobViewV2', in_signature='xs')
    @dbus.service.method('org.kde.JobView', in_signature='xs')
    def setTotalAmount(self, amount, unit):
        self.total = int(amount)
        self.unit = str(unit)
        self.emit_update()

    @dbus.service.method('org.kde.JobViewV2', in_signature='x')
    @dbus.service.method('org.kde.JobView', in_signature='x')
    def setSpeed(self, speed):
        self.speed = int(speed)
        self.emit_update()

    @dbus.service.method('org.kde.JobViewV2', in_signature='s')
    @dbus.service.method('org.kde.JobView', in_signature='s')
    def terminate(self, error_message):
        self.emit_update("terminated" if not error_message else "failed")
        self.remove_from_connection()

    @dbus.service.method('org.kde.JobViewV2', in_signature='')
    @dbus.service.method('org.kde.JobView', in_signature='')
    def clear(self):
        self.emit_update("cleared")
        self.remove_from_connection()

class JobViewServer(dbus.service.Object):
    def __init__(self, bus):
        dbus.service.Object.__init__(self, bus, '/JobViewServer')
        self.bus = bus
        self.job_counter = 0

    @dbus.service.method('org.kde.JobViewServer', in_signature='ssi', out_signature='o')
    def requestView(self, appname, appicon, capabilities):
        self.job_counter += 1
        job_path = f"/JobViewServer/job_{self.job_counter}"
        JobView(self.bus, job_path, appname, appicon, capabilities)
        return dbus.ObjectPath(job_path)

class ProgressServer(dbus.service.Object):
    def __init__(self, bus):
        dbus.service.Object.__init__(self, bus, '/ProgressServer')
        self.bus = bus

    @dbus.service.method('org.kde.JobViewServer', in_signature='sssus')
    def UpdateProgress(self, job_id, app_name, app_icon, percent, message):
        data = {
            "event": "update",
            "id": job_id,
            "appName": app_name,
            "appIcon": app_icon,
            "percent": int(percent),
            "message": message,
            "state": "running" if percent < 100 else "completed"
        }
        print(json.dumps(data), flush=True)

    @dbus.service.method('org.kde.JobViewServer', in_signature='s')
    def TerminateProgress(self, job_id):
        data = {
            "event": "terminate",
            "id": job_id
        }
        print(json.dumps(data), flush=True)

if __name__ == '__main__':
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    session_bus = dbus.SessionBus()
    
    try:
        # Grabbing org.kde.JobViewServer
        name = dbus.service.BusName('org.kde.JobViewServer', session_bus)
        server = JobViewServer(session_bus)
        cli_server = ProgressServer(session_bus)
        print(json.dumps({"event": "status", "status": "running"}), flush=True)
    except Exception as e:
        print(json.dumps({"event": "error", "message": str(e)}), flush=True)
        sys.exit(1)

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
