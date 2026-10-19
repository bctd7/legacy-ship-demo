"""Bounded supplement for canonical segments 19,20,21, using exported GLB geometry.
No Blender, edits, dynamic simulation, or frame sampling. Convex continuous covers.
"""
from pathlib import Path
import json,struct,math,itertools,hashlib,sys
import numpy as np
from scipy.spatial import ConvexHull
ROOT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parent.parent
EPS=1e-6; PAD=1e-7
raw=(ROOT/'assets/bridge_v2_assembly.glb').read_bytes();length=struct.unpack_from('<I',raw,12)[0]
doc=json.loads(raw[20:20+length]);blob=raw[28+length:]
def read(index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
    dtype={5126:'<f4',5125:'<u4',5123:'<u2'}[a['componentType']]
    dim={'VEC3':3,'SCALAR':1}[a['type']];size=np.dtype(dtype).itemsize
    return np.ndarray((a['count'],dim),dtype=dtype,buffer=blob,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dim*size),size)).copy()
meshes={}
for node in doc['nodes']:
    name=node['name']
    if name.startswith('Hoist_') or 'mesh' not in node:continue
    vertices=[];triangles=[]
    for primitive in doc['meshes'][node['mesh']]['primitives']:
        V=read(primitive['attributes']['POSITION']).astype(float)
        indices=read(primitive['indices']).astype(int).reshape(-1,3)
        vertices.append(V);triangles.append(V[indices])
    V=np.concatenate(vertices);T=np.concatenate(triangles)
    meshes[name]={'V':V,'T':T,'lo':V.min(axis=0),'hi':V.max(axis=0)}
def convex(vertices):
    V=np.unique(vertices,axis=0);h=ConvexHull(V);eq=np.unique(np.round(h.equations,13),axis=0)
    return {'V':V[h.vertices],'N':eq[:,:3],'b':-eq[:,3],'lo':V.min(axis=0),'hi':V.max(axis=0)}
def box(center,size,M):
    return np.array([center+M@np.array([x*size[0]/2,y*size[1]/2,z*size[2]/2]) for x,y,z in itertools.product([-1,1],repeat=3)])
def deck_pieces(name):
    i=int(name[-2:])-1;R=.16/(1-math.cos(math.radians(20)))
    nodes=[np.array([R*math.sin(math.radians(t)),0,.22+R*(math.cos(math.radians(t))-.5)]) for t in range(-60,61,20)]
    a,b=nodes[i],nodes[i+2];theta=math.atan2((b-a)[2],(b-a)[0]);normal=np.array([-math.sin(theta),0,math.cos(theta)])
    center=(a+b)/2+normal*.08;M=np.array([[math.cos(theta),0,-math.sin(theta)],[0,1,0],[math.sin(theta),0,math.cos(theta)]])
    lane=.90+.15*(i%3-1)
    result=[box(center+M@np.array([0,0,.30]),(.90,1.34,.075),M)*.1]
    for x in [-.30,.30]:
        result.append(box(center+M@np.array([x,0,.2425]),(.12,2*lane+.13,.05),M)*.1)
        for y in [-lane,lane]:result.append(box(center+M@np.array([x,y,.15375]),(.12,.10,.1475),M)*.1)
    C=np.array([[1,0,0],[0,0,1],[0,-1,0]])
    return [convex((v+np.sign((v-v.mean(axis=0))@M)@M.T*PAD)@C.T) for v in result]
def clip(poly,N,b):
    p=np.asarray(poly)
    for n,limit in zip(N,b):
        if len(p)==0:break
        dist=p@n-limit;inside=dist<=0
        if inside.all():continue
        if not inside.any():return np.empty((0,3))
        q=[]
        for j in range(len(p)):
            k=(j+1)%len(p)
            if inside[j]:q.append(p[j])
            if inside[j]!=inside[k]:q.append(p[j]+dist[j]/(dist[j]-dist[k])*(p[k]-p[j]))
        p=np.array(q)
    return p
def area(poly):
    return sum(np.linalg.norm(np.cross(poly[k]-poly[0],poly[k+1]-poly[0]))*.5 for k in range(1,len(poly)-1))
def covered(triangle,pieces):
    fragments=[triangle]
    for piece in pieces:
        remains=[]
        for fragment in fragments:
            inner=fragment
            for n,b in zip(piece['N'],piece['b']):
                outside=clip(inner,np.array([-n]),np.array([-b]))
                if area(outside)>1e-22:remains.append(outside)
                inner=clip(inner,np.array([n]),np.array([b]))
                if len(inner)==0:break
        fragments=remains
        if not fragments:return True
    return sum(area(f) for f in fragments)<=1e-20
def inside(point,triangles):
    votes=[];e1=triangles[:,1]-triangles[:,0];e2=triangles[:,2]-triangles[:,0]
    for direction in [(1,.371,.193),(.283,1,.419),(.137,.293,1),(1,-.612,.229),(-.317,1,-.733)]:
        direction=np.array(direction);direction/=np.linalg.norm(direction)
        h=np.cross(direction,e2);a=np.einsum('ij,ij->i',e1,h);valid=np.abs(a)>1e-12
        inv=np.zeros_like(a);inv[valid]=1/a[valid]
        s=point-triangles[:,0];u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=inv*(q@direction);t=inv*np.einsum('ij,ij->i',e2,q)
        hits=t[valid&(u>=-1e-10)&(v>=-1e-10)&(u+v<=1+1e-10)&(t>1e-8)]
        votes.append(len(np.unique(np.round(hits,8)))%2)
    return sum(votes)>=3
def sweep_hit(sweep,obstacle,offset):
    lo=obstacle['lo']+offset;hi=obstacle['hi']+offset
    if np.any(np.minimum(sweep['hi'],hi)-np.maximum(sweep['lo'],lo)<=EPS):return None
    triangles=obstacle['T']+offset
    keep=np.all(triangles.max(axis=1)>=sweep['lo']+EPS,axis=1)&np.all(triangles.min(axis=1)<=sweep['hi']-EPS,axis=1)
    candidates=triangles[keep]
    if len(candidates):
        outside=np.any(np.all(candidates@sweep['N'].T-(sweep['b']-EPS)>0,axis=1),axis=1)
        for triangle in candidates[~outside]:
            if len(clip(triangle,sweep['N'],sweep['b']-EPS)):return 'obstacle_surface_enters_contracted_sweep'
    center=sweep['V'].mean(axis=0)
    if np.all(sweep['N']@center<sweep['b']-EPS) and inside(center,triangles):return 'sweep_enclosed_in_obstacle'
    return None
data=json.loads((ROOT/'content.json').read_text(encoding='utf-8'));parts=data['parts'];fixtures=data['fixtures']
report={'segments':[],'tolerance_m':EPS,'deck_triangle_coverage':{},'limits':['Only canonical missing segments 19,20,21. Kinematic conservative covers; no material strength or gravity.','Normalized convex planes contracted by 0.001 mm, as in original certificate.']}
pieces={}
for name in ['Deck_panel_04','Deck_panel_05']:
    pieces[name]=deck_pieces(name)
    bad=[i for i,t in enumerate(meshes[name]['T']) if not covered(t,pieces[name])]
    report['deck_triangle_coverage'][name]={'uncovered_triangle_indices':bad,'triangles':len(meshes[name]['T'])}
    assert not bad,(name,bad[:3])
for step in data['steps'][18:]:
    start=np.array(step['path']['from_m']);end=np.array(step['path']['to_m']);moving=step['moving'];hits=[];tests=0
    parked={name:np.zeros(3) for name in meshes}
    for other in data['steps']:
        if int(other['index'])>=int(step['index']) and int(other['index'])<21:
            for name in other['moving']:parked[name]=np.array(other['path']['from_m'])
    for name in moving:
        covers=pieces.get(name,[convex(meshes[name]['V'])])
        for piece in covers:
            sweep=convex(np.vstack([piece['V']+start,piece['V']+end]))
            for obstacle in meshes:
                if obstacle in moving:continue
                tests+=1;hit=sweep_hit(sweep,meshes[obstacle],parked[obstacle])
                if hit:hits.append({'moving':name,'obstacle':obstacle,'kind':hit})
    report['segments'].append({'index':step['index'],'continuous_cover_pairs':tests,'unresolved_candidates':hits})
    print('TAIL_SEGMENT',step['index'],'PAIRS',tests,'CANDIDATES',len(hits),flush=True)
report['status']='PASS' if all(not s['unresolved_candidates'] for s in report['segments']) else 'REVIEW_REQUIRED'
report['inputs_sha256']={'assets/bridge_v2_assembly.glb':hashlib.sha256((ROOT/'assets/bridge_v2_assembly.glb').read_bytes()).hexdigest()}
report['trajectory_sha256']=hashlib.sha256(json.dumps([{'moving':s['moving'],'path':s['path']} for s in data['steps']],sort_keys=True).encode()).hexdigest()
(ROOT/'reference/remaining_paths_certificate.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
assert report['status']=='PASS',report
