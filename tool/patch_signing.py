"""Makes the release build use DROM's own fixed key (private key from CI secrets).

Without this, Gradle signs every build with a freshly generated "Android
Debug" key, so Android refuses to install a new build over the old one
("package conflicts with an existing package"). Run after `flutter create`."""
import os
import sys

# The private release key comes from CI secrets (see the workflow):
# SDM_KEYSTORE / SDM_STORE_PASS / SDM_KEY_ALIAS / SDM_KEY_PASS.
for need in ("SDM_KEYSTORE", "SDM_STORE_PASS", "SDM_KEY_ALIAS"):
    if not os.environ.get(need):
        sys.exit(f"{need} is not set")
KEYSTORE = os.path.abspath(os.environ["SDM_KEYSTORE"])
STORE_PASS = os.environ["SDM_STORE_PASS"]
KEY_ALIAS = os.environ["SDM_KEY_ALIAS"]
KEY_PASS = os.environ.get("SDM_KEY_PASS") or STORE_PASS
if not os.path.exists(KEYSTORE):
    sys.exit(f"{KEYSTORE} not found")

kts = "android/app/build.gradle.kts"
groovy = "android/app/build.gradle"

if os.path.exists(kts):
    path, kind = kts, "kts"
elif os.path.exists(groovy):
    path, kind = groovy, "groovy"
else:
    sys.exit("android/app/build.gradle(.kts) not found")

with open(path, encoding="utf-8") as f:
    s = f.read()

if "drom_fixed" in s:
    print("already patched")
    sys.exit(0)

if kind == "kts":
    block = (
        "    signingConfigs {\n"
        '        create("drom_fixed") {\n'
        f'            storeFile = file("{KEYSTORE}")\n'
        f'            storePassword = "{STORE_PASS}"\n'
        f'            keyAlias = "{KEY_ALIAS}"\n'
        f'            keyPassword = "{KEY_PASS}"\n'
        "        }\n"
        "    }\n"
    )
    new_cfg = 'signingConfig = signingConfigs.getByName("drom_fixed")'
    old_cfgs = [
        'signingConfig = signingConfigs.getByName("debug")',
        "signingConfig = signingConfigs.debug",
    ]
else:
    block = (
        "    signingConfigs {\n"
        "        drom_fixed {\n"
        f"            storeFile file('{KEYSTORE}')\n"
        f"            storePassword '{STORE_PASS}'\n"
        f"            keyAlias '{KEY_ALIAS}'\n"
        f"            keyPassword '{KEY_PASS}'\n"
        "        }\n"
        "    }\n"
    )
    new_cfg = "signingConfig signingConfigs.drom_fixed"
    old_cfgs = [
        "signingConfig signingConfigs.debug",
        'signingConfig = signingConfigs.getByName("debug")',
    ]

# 1) add the signing config at the start of the android { } block
i = s.find("android {")
if i < 0:
    sys.exit("no android { block found")
j = s.index("\n", i) + 1
s = s[:j] + block + s[j:]

# 2) release builds use it
done = False
for old in old_cfgs:
    if old in s:
        s = s.replace(old, new_cfg)
        done = True
        break
if not done:
    # no release signingConfig line: add one inside release { }
    k = s.find("release {")
    if k < 0:
        sys.exit("no release { block found")
    k = s.index("\n", k) + 1
    s = s[:k] + "            " + new_cfg + "\n" + s[k:]

with open(path, "w", encoding="utf-8") as f:
    f.write(s)
print("release builds are signed with", KEYSTORE)
