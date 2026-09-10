"""Release Compose ports held by a native copy of this project's Python server."""

import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


def is_project_server(pid):
    try:
        proc = Path('/proc') / str(pid)
        args = (proc / 'cmdline').read_bytes().split(b'\0')
        if not Path(os.fsdecode(args[0])).name.startswith('python'):
            return False
        cwd = (proc / 'cwd').resolve()
        for arg in args[1:]:
            script = (cwd / os.fsdecode(arg)).resolve()
            if (script.name == 'server.py' and script.parent.name == 'Servidor'
                    and script.parent.parent.name == 'John-Deere-Multi-Agent-System'
                    and (script.parent.parent / 'johndeere/simulation.py').is_file()):
                return True
    except (OSError, ValueError):
        pass
    return False


def listeners(ports):
    expression = '( ' + ' or '.join(f'sport = :{p}' for p in ports) + ' )'
    result = subprocess.run(['ss', '-H', '-ltnp', expression],
                            check=True, capture_output=True, text=True)
    return {int(pid) for pid in re.findall(r'pid=(\d+)', result.stdout)}


def main():
    config = json.load(sys.stdin)
    ports = {int(port['published'])
             for service in config['services'].values()
             for port in service.get('ports', []) if 'published' in port}
    if not ports:
        return
    targets = {pid for pid in listeners(ports) if is_project_server(pid)}
    for pid in targets:
        # Recheck identity immediately before sending a graceful termination signal.
        if is_project_server(pid):
            print(f'Stopping local John Deere server (PID {pid}) to free Docker ports.',
                  flush=True)
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 10
    while targets & listeners(ports):
        if time.monotonic() >= deadline:
            sys.exit('Local server did not release its ports after 10 seconds. '
                     'Stop it manually and retry.')
        time.sleep(0.25)


if __name__ == '__main__':
    main()
