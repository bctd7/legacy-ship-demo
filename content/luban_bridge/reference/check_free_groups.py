"""Offline conservative commutation certificate; no geometry edits or runtime physics."""
from pathlib import Path
import struct,json,hashlib,itertools,sys
import numpy as np

arguments=[arg for arg in sys.argv[1:] if not arg.startswith('--')]
root=Path(arguments[0]).resolve() if arguments else Path(__file__).resolve().parent.parent
data=json.loads((root/'content.json').read_text(encoding='utf-8'))
def positions(path):
    raw=path.read_bytes(); length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]); blob=raw[28+length:]; result={}
    for node in doc['nodes']:
        if 'mesh' not in node:continue
        arrays=[]
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            accessor=doc['accessors'][primitive['attributes']['POSITION']]
            assert accessor['componentType']==5126 and accessor['type']=='VEC3'
            view=doc['bufferViews'][accessor['bufferView']]
            offset=view.get('byteOffset',0)+accessor.get('byteOffset',0)
            arrays.append(np.ndarray((accessor['count'],3),dtype='<f4',buffer=blob,offset=offset,strides=(view.get('byteStride',12),4)).astype(float))
        result[node['name']]=np.concatenate(arrays)
    return result
assembly=positions(root/'assets/bridge_v2_assembly.glb')
final=positions(root/'assets/bridge_v2_final.glb')
for name in data['parts']:
    assert np.allclose(np.min(assembly[name],axis=0),np.min(final[name],axis=0),atol=1e-8)
    assert np.allclose(np.max(assembly[name],axis=0),np.max(final[name],axis=0),atol=1e-8)
def swept(step):
    points=assembly[step['part_id']]
    start=np.array(step['path']['from_m']);end=np.array(step['path']['to_m'])
    return points.min(axis=0)+np.minimum(start,end),points.max(axis=0)+np.maximum(start,end)
groups=[data['steps'][:10],data['steps'][10:15],data['steps'][15:20]]
report={'method':'Conservative complete translation-sweep AABBs computed from every exported POSITION vertex, not sampled animation frames. Disjoint AABBs imply disjoint physical sweeps. Only within-stage permutations are enabled.',
        'units':'metres','separation_guard_m':1e-6,'pairs':[],
        'proof_limits':['The canonical cross-stage sequence is retained. Cross-stage AABB overlaps are broad-phase possibilities, not certified collisions.','Original source certificate is reused for earlier stages, bases and temporary fixtures. Removing pending, off-workspace pieces cannot introduce a collision.','Only one action animates at a time. No gravity, friction, strength or external handling model.']}
for group in groups:
    for a,b in itertools.combinations(group,2):
        alo,ahi=swept(a);blo,bhi=swept(b)
        gaps=np.maximum(blo-ahi,alo-bhi)
        axis=int(np.argmax(gaps));clearance=float(gaps[axis])
        assert clearance>1e-6,(a['part_id'],b['part_id'])
        report['pairs'].append({'a':a['part_id'],'b':b['part_id'],'separating_axis':'XYZ'[axis],'separation_m':clearance})
source_report=root/'reference/path_validation.json'
source=json.loads(source_report.read_text(encoding='utf-8'))
assert source['strict_sweep_candidates']==[] and [s['index'] for s in source['steps']]==list(range(1,19))
assert all(not s['unresolved_candidates'] for s in source['steps'])
tail=json.loads((root/'reference/remaining_paths_certificate.json').read_text(encoding='utf-8'))
assert tail['status']=='PASS' and [s['index'] for s in tail['segments']]==[19,20,21]
assert tail['trajectory_sha256']==hashlib.sha256(json.dumps([{'moving':s['moving'],'path':s['path']} for s in data['steps']],sort_keys=True).encode()).hexdigest()
report['canonical_segments_covered']={'original_progress_report':list(range(1,19)),'supplement':[19,20,21]}
report['supplement_sha256']=hashlib.sha256((root/'reference/remaining_paths_certificate.json').read_bytes()).hexdigest()
report['source_sha256']={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ['assets/bridge_v2_final.glb','assets/bridge_v2_assembly.glb','reference/path_validation.json']}
report['pair_count']=len(report['pairs'])
report['minimum_separation_m']=min(p['separation_m'] for p in report['pairs'])
report['groups']=[{'id':name,'members':[s['part_id'] for s in group]} for name,group in zip(['beams','rods','decks'],groups)]
report['conservative_cross_stage_sweep_aabb_candidates']=[]
for earlier,later in [(groups[0],groups[1]),(groups[1],groups[2])]:
    pairs=[]
    for a,b in itertools.product(earlier,later):
        alo,ahi=swept(a);points=assembly[b['part_id']];blo=points.min(axis=0);bhi=points.max(axis=0)
        if np.all(np.maximum(blo-ahi,alo-bhi)<=1e-6):pairs.append([a['part_id'],b['part_id']])
    report['conservative_cross_stage_sweep_aabb_candidates'].append(pairs)
report['result']='PASS_WITHIN_GROUP_PERMUTATIONS_ONLY'
(root/'reference/free_order_certificate.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if '--write-policy' in sys.argv:
    beam_ids=[s['part_id'] for s in groups[0]];rod_ids=[s['part_id'] for s in groups[1]]
    for group,required,reason in [(groups[0],[],'临时托柱在位，梁件同组可任选顺序。'),(groups[1],beam_ids,'先装齐梁件；当前保守保留已验证的先梁后杆通道。'),(groups[2],rod_ids,'先穿齐圆杆；当前只开放已验证的先杆后桥面通道。')]:
        for step in group:
            step['requires']=required.copy();step['dependency_reason']=reason;step['action_kind']='install'
    release=data['steps'][20]
    release['requires']=[s['part_id'] for s in data['steps'][:20]]
    release['dependency_reason']='所有20个可装正式构件就位后，才可撤出临时支撑。'
    release['action_kind']='withdraw'
    data['ruleset_version']='partial_order_1'
    data['installable_part_ids']=[s['part_id'] for s in data['steps'][:20]]
    data['withdraw_action_id']=release['part_id']
    data['assembly_policy']={'groups':report['groups'],'cross_group_order':['beams','rods','decks','withdraw'],'certificate':'res://content/luban_bridge/reference/free_order_certificate.json'}
    (root/'content.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

print('CERTIFICATE_PASS pairs=',len(report['pairs']),'min_gap_mm=',report['minimum_separation_m']*1000)
