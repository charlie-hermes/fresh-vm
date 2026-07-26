import socket


def can_connect(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=2):
            return True
    except OSError:
        return False


assert can_connect("172.30.0.1", 3100), "Paperclip route is unavailable"
for denied_host, denied_port in (
    ("172.30.0.1", 22),
    ("172.30.0.1", 54329),
    ("169.254.169.254", 80),
):
    assert not can_connect(denied_host, denied_port), (
        f"prohibited route reachable: {denied_host}:{denied_port}"
    )
print("network probes passed")
