# Preflight + code generation: design/*.json -> game/scripts/data.gd
# Usage: python tools/gen.py <Black & White folder>   (only reads from it)
import csv, json, math, os, re, sys
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BW = sys.argv[1]
S = {n[:-5]: json.load(open(os.path.join(R, 'design', n), encoding='utf-8')) for n in os.listdir(os.path.join(R, 'design')) if n.endswith('.json')}
mesh_pairs = re.findall(r'(MSH_[A-Z0-9_]+)\s*=\s*(\d+)', open(os.path.join(BW, 'Data/AllMeshes.h')).read())
meshes = {name for name, _ in mesh_pairs}
mesh_ids = {int(index) for _, index in mesh_pairs}
script = open(os.path.join(BW, 'Scripts/Land1.txt'), encoding='latin1').read()
problems = []
def filled(value, cell):
    if value is None or value == '':
        problems.append(f'{cell} empty')
    elif isinstance(value, dict):
        for k, v in value.items(): filled(v, f'{cell}.{k}')
    elif isinstance(value, list):
        for i, v in enumerate(value): filled(v, f'{cell}[{i}]')
for sheet, rows in S.items():
    cols = set().union(*[r.keys() for r in rows])
    for i, r in enumerate(rows):
        for c in cols:
            if c not in r or r[c] is None or r[c] == "":
                problems.append(f"{sheet}[{i}].{c} empty")
        if 'mesh' in r and r['mesh'] not in meshes:
            problems.append(f"{sheet}[{i}] mesh {r['mesh']} not in game")
        filled(r, f'{sheet}[{i}]')
        for c in ['mesh_file', 'good_file', 'evil_file', 'animation_file']:
            if c in r and not os.path.isfile(os.path.join(BW, r[c])):
                problems.append(f'{sheet}[{i}].{c} missing host file')
for r in S['advisers']:
    if not os.path.isfile(os.path.join(BW, r['file'])):
        problems.append(f"adviser {r['id']} source file missing")
    else:
        with open(os.path.join(BW, r['file']), 'rb') as f:
            if (r['speech_clip'].split('/')[-1] + '.anm').encode('ascii') not in f.read():
                problems.append(f"adviser {r['id']} original speech animation missing")
for r in S['port_modules']:
    if not os.path.isfile(os.path.join(BW, r['source'])):
        problems.append(f"module {r['id']} source file missing")
    if not os.path.isfile(os.path.join(R, 'game/scripts', r['reader'])):
        problems.append(f"module {r['id']} reader missing")
opcodes = [r['id'] for r in S['story_opcodes']]
if sorted(opcodes) != list(range(31)):
    problems.append('story_opcodes must define each original opcode 0..30 exactly once')
pose_rules = next((row['params'] for row in S['port_rules'] if row['id'] == 'skeleton_pose'), {})
expected_pose_rules = {'input_space':'parent_local_absolute', 'engine_pose':'parent_local_absolute',
                       'initial_pose':'model_rest', 'basis_decomposition':'signed_scale'}
if pose_rules != expected_pose_rules:
    problems.append('skeleton_pose must specify verified Godot 4 parent-local poses, rest initialization and signed scale')
story_sources = {r['id'] for r in S['port_modules']}
for row in S['story_vm']:
    if row['script_source'] not in story_sources:
        problems.append(f"story_vm.{row['id']}.script_source does not resolve")
    if row['native_policy'] != 'reject_unbound':
        problems.append(f"story_vm.{row['id']} must stop at unbound game behaviour")
native_ids = [r['id'] for r in S['story_natives']]
if len(native_ids) != len(set(native_ids)):
    problems.append('story_natives contains duplicate function IDs')
search_rules = {r['id']: r for r in S['story_search_rules']}
search_types = [r['object_type'] for r in S['story_search_rules']]
if len(search_types) != len(set(search_types)):
    problems.append('story_search_rules contains duplicate object types')
create_rules = {r['id']: r for r in S['story_create_rules']}
for row in S['story_natives']:
    if row['handler'] == 'exact_landmark' and not {'exact_feature','exact_abode'}.issubset(search_rules):
        problems.append('story native exact_landmark search rules are missing')
    if row['handler'] == 'create_marker' and row['handler'] not in create_rules:
        problems.append('story native create_marker rule is missing')
for rule in S['story_search_rules']:
    if rule['position_tolerance'] <= 0 or rule['ambiguous_result'] != 'block' or rule['exclude_scripted_supported']:
        problems.append(f"story_search_rules.{rule['id']} must block unsupported or ambiguous object searches")
for rule in S['story_create_rules']:
    if rule['maximum_created'] <= 0 or rule['representation'] != 'position_only':
        problems.append(f"story_create_rules.{rule['id']} has invalid marker creation limits")
landmark_rules = {row['id']:row for row in S['landmark_animation_rules']}
if 'scripted' not in landmark_rules or landmark_rules['scripted']['speed'] <= 0 or landmark_rules['scripted']['root_translation'] != 'preserve':
    problems.append('landmark_animation_rules.scripted is missing or invalid')
if not os.path.isfile(os.path.join(R, 'game/scripts/original_landmark.gd')):
    problems.append('original landmark animation controller is missing')
native_reader = os.path.join(R, 'game/scripts/story_natives.gd')
if os.path.isfile(native_reader):
    native_code = open(native_reader, encoding='utf-8').read()
    for row in S['story_natives']:
        if f'"{row["handler"]}"' not in native_code:
            problems.append(f"story_natives.{row['id']}.handler is not implemented")
    story_rules = next((row['params'] for row in S['port_rules'] if row['id']=='story'), {})
    if story_rules.get('native_bindings_implemented') != len(S['story_natives']):
        problems.append('story native binding count differs between sheets')
audio_sources = {r['id']:r for r in S['audio_sources']}
for row in S['audio_sources']:
    if not os.path.isfile(os.path.join(BW, row['path'])):
        problems.append(f"audio_sources.{row['id']} missing original file")
    if not os.path.isfile(os.path.join(R, 'game/scripts', row['reader'])):
        problems.append(f"audio_sources.{row['id']} reader missing")
for row in S['audio_decoder']:
    if not os.path.isfile(os.path.join(R, 'game/bin', row['executable'])):
        problems.append(f"audio_decoder.{row['id']} helper missing")
    if not os.path.isfile(os.path.join(R, 'game/scripts', row['reader'])):
        problems.append(f"audio_decoder.{row['id']} reader missing")
audio_decoders = {r['id'] for r in S['audio_decoder']}
music_modes = {r['id'] for r in S['music_modes']}
for row in S['music_modes']:
    if row['source'] not in audio_sources or row['decoder'] not in audio_decoders:
        problems.append(f"music_modes.{row['id']} audio source or decoder missing")
    if row['min_alignment'] > row['max_alignment']:
        problems.append(f"music_modes.{row['id']} alignment range invalid")
for row in S['music_rules']:
    for col in ('default_mode','good_mode','evil_mode'):
        if row[col] not in music_modes:
            problems.append(f"music_rules.{row['id']}.{col} does not resolve")
dialogue_data = open(os.path.join(BW,audio_sources['dialogue_text']['path']), 'rb').read().decode('utf-16')
bank_data = open(os.path.join(BW,audio_sources['adviser_bank']['path']), 'rb').read()
for row in S['story_dialogue']:
    if row['bank'] not in audio_sources or row['text_source'] not in audio_sources:
        problems.append(f"story_dialogue.{row['id']} source reference missing")
    if f'"{row["id"]}"' not in dialogue_data:
        problems.append(f"story_dialogue.{row['id']} original subtitle missing")
    if (row['id'] + '.wav').encode('ascii') not in bank_data:
        problems.append(f"story_dialogue.{row['id']} original voice missing")
animation_profiles = {r['id'] for r in S['villager_animations']}
for r in S['villagers']:
    if r['animation_profile'] not in animation_profiles:
        problems.append(f"villagers.{r['villager_type']}.animation_profile does not resolve")
# Verify animation names in original archive headers, without extracting assets.
anm = open(os.path.join(BW, 'Data/AllAnims.anm'), 'rb').read()
ap, body = 8, None
while ap + 36 <= len(anm):
    nm = anm[ap:ap+32].split(b'\0')[0]
    size = int.from_bytes(anm[ap+32:ap+36], 'little')
    if nm == b'Body': body = anm[ap+36:ap+36+size]
    ap += 36 + size
animation_names = set()
if body:
    count = int.from_bytes(body[4:8], 'little')
    for ai in range(count):
        off = int.from_bytes(body[8+ai*8:12+ai*8], 'little')
        animation_names.add(body[off:off+32].split(b'\0')[0].decode('ascii'))
for row in S['villager_animations']:
    for col, value in row.items():
        if col != 'id' and value not in animation_names:
            problems.append(f"villager_animations.{row['id']}.{col} missing original clip")
# Verify each action->clip reference against each player's actual original CBN.
import struct
for creature in S['creatures']:
    with open(os.path.join(BW, creature['animation_file']), 'rb') as f: cbn = f.read()[44:]
    ver = struct.unpack_from('<I', cbn, 4)[0]
    spec = open(os.path.join(BW, f'Data/ctrspec{ver}.txt')).read().splitlines()
    category, clips = '', []
    for line in spec[1:]:
        if line == 'E': break
        if line.startswith('='): category = line[1:]
        elif line: clips.append(category + '/' + line[1:])
    for action in S['creature_actions']:
        clip = action['clip']
        if clip not in clips or not struct.unpack_from('<I', cbn, 236 + clips.index(clip) * 4)[0]:
            problems.append(f"creature_actions.{action['id']}.clip {clip} missing for {creature['id']}")
for t in set(re.findall(r'"([A-Z]+_ABODE_[A-Z_]+)"', script)):
    if t not in {r['abode_type'] for r in S['abodes']}:
        problems.append(f"abode {t} used by island has no row")
for t in set(re.findall(r'^CREATE_VILLAGER_POS\("[^"]+", "[^"]+", "([A-Z_]+)"', script, re.M)):
    if t not in {r['villager_type'] for r in S['villagers']}:
        problems.append(f"villager {t} used by island has no row")
for t in set(int(x) for x in re.findall(r'^CREATE_NEW_TREE\([-0-9]+, "[^"]+", (\d+)', script, re.M)):
    if t not in {r['tree_type'] for r in S['trees']}:
        problems.append(f"tree type {t} has no row")
for t in set(re.findall(r'^CREATE_NEW_FEATURE\("[^"]+", "([^"]+)"', script, re.M)):
    if t not in {r['feature'] for r in S['features']}:
        problems.append(f"feature {t} has no row")
host_info = open(os.path.join(BW, 'Scripts/info.dat'), 'rb').read()
ip, info = 8, None
while ip + 36 <= len(host_info):
    name = host_info[ip:ip+32].split(b'\0')[0]
    size = struct.unpack_from('<I', host_info, ip+32)[0]
    if ip + 36 + size > len(host_info):
        problems.append('original info.dat block is truncated')
        break
    if name == b'Info': info = host_info[ip+36:ip+36+size]
    ip += 36 + size
fmt = next((r for r in S['host_info_formats'] if info is not None and r['info_size'] == len(info)), None)
static_categories = {r['id']:r for r in S['statics']}
physics_profiles = {r['id'] for r in S['physics_profiles']}
for row in S['statics']:
    if row['pickable'] and row['physics'] not in physics_profiles:
        problems.append(f"statics.{row['id']}.physics does not resolve")
if fmt is None:
    problems.append('original info.dat version is not supported')
else:
    influence_rules = {r['id']: r for r in S['influence_rules']}
    influence = influence_rules.get('scripted_object', {})
    if (set(influence_rules) != {'scripted_object'} or
            influence.get('settings_source') not in {r['id'] for r in S['sources']} or
            influence.get('host_format') != fmt['id'] or influence.get('distance') != 'horizontal' or
            influence.get('curve') != 'native_1_2_piecewise' or influence.get('outer_tail') != 0.2):
        problems.append('original influence rule has missing or unsupported references')
    offset = fmt['influence_offset']
    if fmt['influence_float_count'] != 3 or offset < 0 or offset + 12 > len(info):
        problems.append('original influence settings are truncated')
    else:
        full, gradient, small = struct.unpack_from('<3f', info, offset)
        if not all(math.isfinite(x) for x in (full, gradient, small)) or not (0 < full < 1 and 0 < gradient and full + gradient < 1 and 0 <= small <= 1):
            problems.append('original influence settings are invalid')
    for t in set(int(x) for x in re.findall(r'^CREATE_MOBILE_STATIC\("[^"]+", (\d+)', script, re.M)):
        if t >= fmt['record_count']:
            problems.append(f'original static {t} outside info table')
            continue
        p = fmt['mobile_static_offset'] + fmt['record_size'] * t
        if p + fmt['record_size'] > len(info):
            problems.append(f'original static {t} truncated')
            continue
        object_type = struct.unpack_from('<I', info, p + fmt['object_type_offset'])[0]
        mesh = struct.unpack_from('<I', info, p + fmt['mesh_id_offset'])[0]
        category = struct.unpack_from('<I', info, p + fmt['category_offset'])[0]
        if object_type != fmt['expected_object_type']:
            problems.append(f'original static {t} has an unexpected object type')
        if mesh not in mesh_ids:
            problems.append(f'original static {t} mesh ID {mesh} is absent from host')
        if category not in static_categories:
            problems.append(f'original static {t} category {category} is not implemented')
    animated = {}
    for i in range(fmt['animated_record_count']):
        p = fmt['animated_static_offset'] + i * fmt['animated_record_size']
        if p < 0 or p + fmt['animated_record_size'] > len(info):
            problems.append(f'original animated object {i} truncated')
            continue
        typ = struct.unpack_from('<I', info, p + fmt['animated_type_offset'])[0]
        start = p + fmt['animated_name_offset']
        end = info.find(b'\0', start, start + fmt['animated_name_limit'])
        mesh = struct.unpack_from('<I', info, p + fmt['animated_mesh_offset'])[0]
        animation = struct.unpack_from('<I', info, p + fmt['animated_animation_offset'])[0]
        if end <= start or typ != fmt['animated_expected_type']:
            problems.append(f'original animated object {i} invalid')
            continue
        name = info[start:end].decode('ascii', 'replace')
        animated.setdefault(name, []).append((mesh, animation))
    animated_rows = {row['id']:row for row in S['animated_statics']}
    used_animated = set(re.findall(r'^CREATE_ANIMATED_STATIC\("[^"]+",\s*"([^"]+)"', script, re.M))
    for name in used_animated:
        row = animated_rows.get(name)
        records = animated.get(name, [])
        if not row or row['source'] not in {r['id'] for r in S['sources']}:
            problems.append(f'animated object {name} missing design row or host source')
        elif row['render'] != 'original_rig' or row['animation'] != 'on_script_request':
            problems.append(f'animated object {name} has invalid original animation policy')
        if len(records) != 1:
            problems.append(f'animated object {name} has {len(records)} original records')
            continue
        mesh, animation = records[0]
        if mesh not in mesh_ids or body is None or animation >= count:
            problems.append(f'animated object {name} has invalid original mesh or animation')
    used_animals = set(int(x) for x in re.findall(r'^CREATE_NEW_ANIMAL\("[^"]+",\s*(\d+)', script, re.M))
    for animal in used_animals:
        if animal >= fmt['animal_record_count']:
            problems.append(f'original animal type {animal} outside information table')
            continue
        p = fmt['animal_offset'] + animal * fmt['animal_record_size']
        if p < 0 or p + fmt['animal_record_size'] > len(info):
            problems.append(f'original animal type {animal} record truncated')
            continue
        typ = struct.unpack_from('<I', info, p + fmt['animal_type_offset'])[0]
        subtype = struct.unpack_from('<I', info, p + fmt['animal_subtype_offset'])[0]
        mesh = struct.unpack_from('<I', info, p + fmt['animal_mesh_offset'])[0]
        animation = struct.unpack_from('<I', info, p + fmt['animal_animation_offset'])[0]
        altitude = struct.unpack_from('<f', info, p + fmt['animal_altitude_normal_offset'])[0]
        ages = struct.unpack_from('<' + 'f' * fmt['animal_age_scale_count'], info, p + fmt['animal_age_scale_offset'])
        if typ != fmt['animal_expected_type'] or subtype != animal or mesh not in mesh_ids or body is None or animation >= count or not math.isfinite(altitude) or any(not math.isfinite(x) or x <= 0 for x in ages):
            problems.append(f'original animal type {animal} data is invalid or incomplete')
placement = {row['id']:row for row in S['placement_rules']}
if set(placement) != {'abode','feature','animated_static'}:
    problems.append('placement_rules must cover abode, feature, and animated_static')
for rule in S['placement_rules']:
    if rule['angle_divisor'] <= 0 or rule['scale_divisor'] <= 0:
        problems.append(f"placement_rules.{rule['id']} has invalid divisors")
        continue
    for line in script.splitlines():
        if not line.startswith(rule['command'] + '(') or not line.endswith(')'):
            continue
        args = next(csv.reader([line[len(rule['command']) + 1:-1]], skipinitialspace=True))
        try:
            angle = float(args[rule['angle_index']]) / rule['angle_divisor']
            scale = float(args[rule['scale_index']]) / rule['scale_divisor']
            if not math.isfinite(angle) or not math.isfinite(scale) or scale <= 0:
                raise ValueError('invalid transform')
        except (ValueError, IndexError, TypeError):
            problems.append(f"placement_rules.{rule['id']} cannot parse an original placement")
for f in S['sources']:
    if not os.path.exists(os.path.join(BW, f['file'])):
        problems.append(f"source {f['file']} missing")
    if not os.path.exists(os.path.join(R, 'game/scripts', f['reader'])):
        problems.append(f"reader {f['reader']} not written")
if problems:
    print("PREFLIGHT:"); print("\n".join(problems))
    if any("skipped" not in p for p in problems):
        sys.exit(1)
gd = json.dumps
out = ["# GENERATED by tools/gen.py from design/*.json - edit the sheets, not this file", "extends RefCounted", ""]
out.append("const ABODES := " + gd({r['abode_type']: r['mesh'] for r in S['abodes']}))
out.append("const TREES := " + gd({str(r['tree_type']): {"mesh": r['mesh'], "pickable": r['pickable']} for r in S['trees']}))
out.append("const VILLAGERS := " + gd({r['villager_type']: {"mesh": r['mesh'], "scale": r['scale'], "animation_profile":r['animation_profile']} for r in S['villagers']}))
out.append("const FEATURES := " + gd({r['feature']: r['mesh'] for r in S['features']}))
out.append("const STATICS := " + gd({str(r['id']):r for r in S['statics']}))
out.append("const ACTIONS := " + gd({r['action']: {"belief": r['belief'], "alignment": r['alignment'], "effect": r['effect'], "input": r['input']} for r in S['actions']}))
out.append("const SYSTEMS := " + gd({r['system']: r['params'] for r in S['systems']}))
out.append("const SOURCES := " + gd({r['id']: r['file'] for r in S['sources']}))
for sheet, name in [('creatures','CREATURES'), ('advisers','ADVISERS'), ('creature_actions','CREATURE_ACTIONS'), ('port_modules','PORT_MODULES'), ('physics_profiles','PHYSICS_PROFILES'), ('villager_animations','VILLAGER_ANIMATIONS'), ('villager_skeletons','VILLAGER_SKELETONS'), ('story_opcodes','STORY_OPCODES'), ('story_vm','STORY_VM'), ('story_natives','STORY_NATIVES'), ('story_search_rules','STORY_SEARCH_RULES'), ('story_create_rules','STORY_CREATE_RULES'), ('audio_sources','AUDIO_SOURCES'), ('audio_decoder','AUDIO_DECODER'), ('story_dialogue','STORY_DIALOGUE'), ('music_modes','MUSIC_MODES'), ('music_rules','MUSIC_RULES'), ('host_info_formats','HOST_INFO_FORMATS'), ('animated_statics','ANIMATED_STATICS'), ('placement_rules','PLACEMENT_RULES'), ('landmark_animation_rules','LANDMARK_ANIMATION_RULES'), ('influence_rules','INFLUENCE_RULES')]:
    out.append('const ' + name + ' := ' + gd({str(r['id']):r for r in S[sheet]}))
out.append('const PORT_RULES := ' + gd({r['id']:r['params'] for r in S['port_rules']}))
open(os.path.join(R, 'game/scripts/data.gd'), 'w', encoding='utf-8').write("\n".join(out) + "\n")
print("preflight done; data.gd written:", {k: len(v) for k, v in S.items()})
