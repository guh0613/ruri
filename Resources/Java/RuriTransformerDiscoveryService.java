package org.ruri.launch;

import cpw.mods.modlauncher.serviceapi.ITransformerDiscoveryService;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Collections;
import java.util.List;

/** Supplies the selected transformation archive without exposing it on the initial classpath. */
public final class RuriTransformerDiscoveryService implements ITransformerDiscoveryService {
    @Override
    public List<Path> candidates(Path gameDirectory) {
        String archive = System.getProperty("ruri.optifine.archive");
        if (archive == null || archive.isEmpty()) return Collections.emptyList();
        return Collections.singletonList(Paths.get(archive));
    }
}
