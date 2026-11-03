from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def resolve_asset(name):
    value=str(name).replace('\\','/')
    for old,new in (('host/app/','host/app/recognition/'),('host/model/','host/model/recognition/'),('metrics/fixtures/','metrics/evidence/recognition/fixtures/')):
        if value.startswith(new):return ROOT/value
        if value.startswith(old):return ROOT/(new+value[len(old):])
    return ROOT/value
