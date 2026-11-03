"""Locate the original sealed workspace from the packaged desktop directory."""
from pathlib import Path


def valid_workspace(path):
    path=Path(path)
    return all((path/part).exists() for part in (
        'XCK325Tboshuhecheng/python/m512_active14_release.py',
        '.venv-cos/Scripts/python.exe','HFceshi/m255a.mat'))


def locate_workspace(app):
    app=Path(app).resolve()
    config=app/'workspace.path'
    if config.is_file():
        path=Path(config.read_text(encoding='utf-8-sig').strip()).expanduser()
        if not path.is_absolute():path=app/path
        path=path.resolve()
        if valid_workspace(path):return path
        raise FileNotFoundError('workspace.path指向的原工作区不完整：'+str(path))
    for path in app.parents:
        if valid_workspace(path):return path
    raise FileNotFoundError('未找到原工程、.venv-cos与HFceshi。请先运行host/deploy/configure_desktop.ps1 -WorkspaceRoot 原工作区路径。')
