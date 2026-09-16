import os
from PyInstaller.utils.hooks import collect_all, copy_metadata

project = os.path.abspath(os.path.join(SPECPATH, '../..'))
datas, binaries, hidden = [], [], []
for package in ('mlx', 'mlx_lm', 'tokenizers'):
    data, binary, imports = collect_all(package)
    datas += data
    binaries += binary
    hidden += imports
for package in ('transformers', 'huggingface-hub', 'safetensors', 'regex', 'tqdm', 'numpy'):
    datas += copy_metadata(package)
a = Analysis([os.path.join(SPECPATH, 'server.py')], pathex=[], binaries=binaries,
             datas=datas, hiddenimports=hidden, hookspath=[], hooksconfig={},
             runtime_hooks=[], excludes=['torch', 'tensorflow', 'scipy', 'matplotlib', 'PIL'],
             noarchive=False)
pyz = PYZ(a.pure)
identity = os.environ.get('WTM_MLX_SIGNING_IDENTITY', '-')
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='wtm-mlx-runtime',
          debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
          console=True, target_arch='arm64', codesign_identity=identity)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='wtm-mlx-runtime')
app = BUNDLE(coll, name='WTM MLX Runtime.app', icon=None,
             bundle_identifier='de.powtac.whatthemodel.mlxruntime',
             info_plist={'CFBundleShortVersionString':'1.0.0', 'WTMMLXProtocol':1,
                         'LSBackgroundOnly':True, 'LSMinimumSystemVersion':'15.0'})
