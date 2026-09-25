#!/usr/bin/env python3
"""Rebuild the deterministic Java 8 transformation discovery resource."""
from pathlib import Path
import os
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[2]
source = root / 'Resources/Java/RuriTransformerDiscoveryService.java'
target = root / 'Sources/RuriCore/Resources/LoaderSupport/ruri-transformer-discovery-1.0.jar'
javac = str(Path(os.environ['JAVA_HOME']) / 'bin/javac') if 'JAVA_HOME' in os.environ else 'javac'

with tempfile.TemporaryDirectory(prefix='ruri-loader-support-') as directory:
    work = Path(directory)
    # Compile against the public service signature without packaging a second
    # copy of ModLauncher's interface or requiring a network download to build.
    interface = work / 'cpw/mods/modlauncher/serviceapi/ITransformerDiscoveryService.java'
    interface.parent.mkdir(parents=True)
    interface.write_text('''package cpw.mods.modlauncher.serviceapi;
public interface ITransformerDiscoveryService {
    java.util.List<java.nio.file.Path> candidates(java.nio.file.Path gameDirectory);
}
''')
    classes = work / 'classes'
    subprocess.run([javac, '--release', '8', '-g:none', '-d', str(classes), str(interface), str(source)], check=True)
    entries = {
        'META-INF/MANIFEST.MF': b'Manifest-Version: 1.0\r\nAutomatic-Module-Name: org.ruri.transformer.discovery\r\n\r\n',
        'META-INF/services/cpw.mods.modlauncher.serviceapi.ITransformerDiscoveryService': b'org.ruri.launch.RuriTransformerDiscoveryService\n',
        'org/ruri/launch/RuriTransformerDiscoveryService.class': (classes / 'org/ruri/launch/RuriTransformerDiscoveryService.class').read_bytes(),
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name, data in sorted(entries.items()):
            entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    print(target.relative_to(root))
