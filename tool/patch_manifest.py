"""Adds what SDM needs to the generated Android project:
permissions, app label, the Share intent filter, the download foreground
service, and our own MainActivity.kt / DownloadService.kt."""
import glob
import os
import re
import sys

PATH = "android/app/src/main/AndroidManifest.xml"

PERMS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.MANAGE_EXTERNAL_STORAGE",
    # Android 13+: needed to open a downloaded video / song / picture
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_AUDIO",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.POST_NOTIFICATIONS",
    # background downloads
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.WAKE_LOCK",
    "android.permission.VIBRATE",
    # installing an update that SDM downloaded itself
    "android.permission.REQUEST_INSTALL_PACKAGES",
]

# --- find the package the generated MainActivity.kt lives in
found = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not found:
    sys.exit("generated MainActivity.kt not found")
target = found[0]
with open(target, encoding="utf-8") as f:
    pkg = re.search(r"^package\s+([\w.]+)", f.read(), re.M).group(1)

with open(PATH, encoding="utf-8") as f:
    xml = f.read()

add = ""
for p in PERMS:
    if p not in xml:
        add += f'    <uses-permission android:name="{p}"/>\n'

if "<application" not in xml:
    sys.exit("AndroidManifest.xml has no <application> tag")

xml = xml.replace("<application", add + "    <application", 1)

# http:// links work too, and the old storage model keeps working
if "usesCleartextTraffic" not in xml:
    xml = xml.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
if "requestLegacyExternalStorage" not in xml:
    xml = xml.replace("<application", '<application android:requestLegacyExternalStorage="true"', 1)

# Do not let Android restore old app data (download list, browser history)
# from a Google backup when SDM is uninstalled and installed again.
if "android:allowBackup" in xml:
    xml = re.sub(r'android:allowBackup="[^"]*"', 'android:allowBackup="false"', xml, count=1)
else:
    xml = xml.replace("<application", '<application android:allowBackup="false"', 1)

# app name
xml = re.sub(r'android:label="[^"]*"', 'android:label="SDM"', xml, count=1)

# Accept "Share" of text/links from other apps into the main activity.
if "android.intent.action.SEND" not in xml:
    share_filter = (
        "        <intent-filter>\n"
        '            <action android:name="android.intent.action.SEND"/>\n'
        '            <category android:name="android.intent.category.DEFAULT"/>\n'
        '            <data android:mimeType="text/plain"/>\n'
        "        </intent-filter>\n"
    )
    if "</activity>" not in xml:
        sys.exit("AndroidManifest.xml has no </activity> tag")
    xml = xml.replace("</activity>", share_filter + "    </activity>", 1)

# Links tapped in other apps: SDM shows up in "Open with" and can be chosen
# as the default browser (http / https, VIEW + BROWSABLE).
if 'android:scheme="https"' not in xml:
    view_filter = (
        "        <intent-filter>\n"
        '            <action android:name="android.intent.action.VIEW"/>\n'
        '            <category android:name="android.intent.category.DEFAULT"/>\n'
        '            <category android:name="android.intent.category.BROWSABLE"/>\n'
        '            <data android:scheme="http"/>\n'
        '            <data android:scheme="https"/>\n'
        "        </intent-filter>\n"
    )
    xml = xml.replace("</activity>", view_filter + "    </activity>", 1)

# Foreground service that keeps downloads alive in the background.
if "DownloadService" not in xml:
    service = (
        f'    <service android:name="{pkg}.DownloadService"\n'
        '        android:exported="false"\n'
        '        android:foregroundServiceType="dataSync"/>\n'
    )
    if "</application>" not in xml:
        sys.exit("AndroidManifest.xml has no </application> tag")
    xml = xml.replace("</application>", service + "    </application>", 1)

# Our own FileProvider so downloaded files / the update APK can be handed to
# the video player, installer, etc. from any storage path.
if "SdmFileProvider" not in xml:
    prov = (
        f'    <provider android:name="{pkg}.SdmFileProvider"\n'
        '        android:authorities="${applicationId}.sdmfiles"\n'
        '        android:exported="false"\n'
        '        android:grantUriPermissions="true">\n'
        '        <meta-data android:name="android.support.FILE_PROVIDER_PATHS"\n'
        '            android:resource="@xml/sdm_file_paths"/>\n'
        '    </provider>\n'
    )
    xml = xml.replace("</application>", prov + "    </application>", 1)
    os.makedirs("android/app/src/main/res/xml", exist_ok=True)
    with open("android/app/src/main/res/xml/sdm_file_paths.xml", "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<paths>\n'
                '    <root-path name="root" path="."/>\n</paths>\n')

with open(PATH, "w", encoding="utf-8") as f:
    f.write(xml)

# --- install our Kotlin sources next to the generated MainActivity.kt
import os

target_dir = os.path.dirname(target)
for tpl, out in (
    ("tool/MainActivity.kt.tpl", "MainActivity.kt"),
    ("tool/DownloadService.kt.tpl", "DownloadService.kt"),
):
    with open(tpl, encoding="utf-8") as f:
        kt = f.read().replace("__PACKAGE__", pkg)
    with open(os.path.join(target_dir, out), "w", encoding="utf-8") as f:
        f.write(kt)

print("Manifest patched, Kotlin sources installed for package", pkg)
