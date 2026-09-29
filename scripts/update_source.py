#!/usr/bin/env python3
"""Ajoute la nouvelle version de l'app à la source SideStore (sidestore/source.json)."""
import argparse, datetime, json, os

p = argparse.ArgumentParser()
p.add_argument("--ipa", required=True)
p.add_argument("--version", required=True)
p.add_argument("--build", required=True)
p.add_argument("--repo", required=True)          # ex. fabien/scan-tickets
p.add_argument("--notes", default="")
p.add_argument("--source", default="sidestore/source.json")
a = p.parse_args()

raw = f"https://raw.githubusercontent.com/{a.repo}/main"
owner = a.repo.split("/")[0]

if os.path.exists(a.source):
    with open(a.source, encoding="utf-8") as f:
        src = json.load(f)
else:
    src = {}

src.update({
    "name": "Scan Tickets",
    "subtitle": "Notes de frais à partir de photos de tickets",
    "iconURL": f"{raw}/sidestore/icon.png",
    "website": f"https://github.com/{a.repo}",
    "tintColor": "#4F46E5",
    "nsfw": False,
    "news": src.get("news", []),
})

apps = src.get("apps") or [{}]
app = apps[0]
app.update({
    "name": "Scan Tickets",
    "bundleIdentifier": "com.lemercier.scantickets",
    "developerName": owner,
    "subtitle": "Tickets, notes de frais, export Excel",
    "localizedDescription": "Photographiez vos tickets : l'app lit le montant, la date et le commerçant, "
                            "puis remplit votre note de frais Excel.",
    "iconURL": f"{raw}/sidestore/icon.png",
    "tintColor": "#4F46E5",
    "category": "utilities",
    "appPermissions": {
        "entitlements": [],
        "privacy": {
            "NSCameraUsageDescription": "L'appareil photo sert à scanner vos tickets de caisse.",
            "NSPhotoLibraryUsageDescription": "Accès aux photos pour importer des tickets déjà photographiés.",
        },
    },
})

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
url = f"https://github.com/{a.repo}/releases/download/v{a.version}/ScanTickets.ipa"
size = os.path.getsize(a.ipa)
version = {
    "version": a.version,
    "buildVersion": a.build,
    "date": now,
    "localizedDescription": a.notes.strip() or f"Version {a.version}",
    "downloadURL": url,
    "size": size,
    "minOSVersion": "17.0",
}
versions = [v for v in app.get("versions", []) if v.get("version") != a.version]
app["versions"] = ([version] + versions)[:10]
# Champs de l'ancien format, pour compatibilité
app.update({"version": a.version, "versionDate": now, "versionDescription": version["localizedDescription"],
            "downloadURL": url, "size": size})
src["apps"] = [app]

with open(a.source, "w", encoding="utf-8") as f:
    json.dump(src, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"Source mise à jour : {a.version} ({size} octets)")
