"""Render reviewed deployment templates. Never execute config-file contents."""
import ipaddress
import json
import os
from pathlib import Path
import re
import sys


def validate(directory, port, domain):
    if not re.fullmatch(r"/(?:opt|srv)/[A-Za-z0-9_-]+", directory):
        raise ValueError("安装目录必须为 /opt 或 /srv 下的专用目录（仅字母、数字、下划线、连字符）")
    # On Linux refuse symlinked paths, including /opt or /srv.
    if os.name != "nt":
        p = Path(directory)
        if any(part.is_symlink() for part in [p, *p.parents]):
            raise ValueError("安装路径不能包含符号链接")
    if not re.fullmatch(r"[0-9]{4,5}", str(port)) or not 1024 <= int(port) <= 65535:
        raise ValueError("端口必须为 1024–65535")
    if domain:
        if len(domain) > 253 or not re.fullmatch(r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}", domain):
            raise ValueError("请填写小写 ASCII 域名，不包含协议、端口或路径")
    return int(port)


def render(manifest, directory, port, domain, output):
    port = validate(directory, port, domain)
    release = json.loads(Path(manifest).read_text(encoding="utf-8"))
    ref = release["backend_commit"]
    if not re.fullmatch(r"[a-f0-9]{40}", ref):
        raise ValueError("backend_commit 必须固定为 40 位 SHA")
    caddy = release["caddy_image"]
    if not re.fullmatch(r"caddy:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}", caddy):
        raise ValueError("Caddy 必须固定 digest")
    api = {"build": {"context": f"{directory}/releases/{ref}"},
           "image": f"mvw-secure:{ref}", "restart": "unless-stopped", "init": True,
           "user": "10001:10001", "read_only": True,
           "cap_drop": ["ALL"], "security_opt": ["no-new-privileges:true"],
           "pids_limit": 512, "mem_limit": "3g", "shm_size": "1g",
           "tmpfs": ["/tmp:rw,nosuid,nodev,size=512m,mode=1777"],
           "ports": [f"127.0.0.1:{port}:18610"],
           "environment": {"MUSE2API_PUBLIC_BASE": f"https://{domain}" if domain else "",
                           "MUSE2API_CORS_ORIGINS": ""},
           "volumes": [{"type": "bind", "source": f"{directory}/data", "target": "/app/data"}],
           "logging": {"driver": "json-file", "options": {"max-size": "10m", "max-file": "3"}}}
    compose = {"services": {"api": api}}
    caddyfile = "# HTTPS disabled; private access only.\n"
    if domain:
        compose["services"]["proxy"] = {
            "image": caddy, "user": "10002:10002", "restart": "unless-stopped",
            "read_only": True, "cap_drop": ["ALL"], "security_opt": ["no-new-privileges:true"],
            "ports": ["80:8080", "443:8443"], "depends_on": ["api"],
            "volumes": [{"type": "bind", "source": f"{directory}/{src}", "target": dst, "read_only": ro}
                        for src, dst, ro in [("Caddyfile", "/etc/caddy/Caddyfile", True),
                                            ("caddy-data", "/data", False), ("caddy-config", "/config", False)]],
            "logging": api["logging"]}
        caddyfile = ("{\n  admin off\n  http_port 8080\n  https_port 8443\n}\n"
                     + domain + " {\n  request_body {\n    max_size 48MB\n  }\n  reverse_proxy api:18610\n}\n")
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    (out / "compose.yml").write_text(json.dumps(compose, indent=2)+"\n", encoding="utf-8")
    (out / "Caddyfile").write_text(caddyfile, encoding="utf-8")
    (out / "deployment.json").write_text(json.dumps({"port": port, "domain": domain, "backend_commit": ref}, indent=2)+"\n", encoding="utf-8")


def main():
    action, *args = sys.argv[1:]
    if action == "validate": validate(*args)
    elif action == "render": render(*args)
    elif action == "get": print(json.loads(Path(args[0]).read_text(encoding="utf-8"))[args[1]])
    elif action == "credentials":
        data = json.loads(Path(args[0]).read_text(encoding="utf-8"))
        print("生成接口 Key："+data["api"]+"\n管理员 Key："+data["admin"])
    else: raise ValueError("Unknown action")


if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
