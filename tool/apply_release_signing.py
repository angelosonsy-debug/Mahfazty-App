#!/usr/bin/env python3
"""
apply_release_signing.py

بيتشغّل مرة واحدة جوه bootstrap-android.yml، بعد ما `flutter create` يولّد
android/app/build.gradle (أو build.gradle.kts) الافتراضي. مهمته الوحيدة:

  1. إضافة قراءة android/key.properties (لو موجود) في أول الملف.
  2. إضافة signingConfigs.release يقرأ من key.properties.
  3. تغيير buildTypes.release.signingConfig من signingConfigs.debug
     (سلوك Flutter الافتراضي — ده بالظبط سبب مشكلة "debug-signed release"
     المذكورة في تقرير Audit) إلى signingConfigs.release.

لو الملف مش بالشكل المتوقع (تغيّر template Flutter الافتراضي بشكل جوهري)،
السكريبت بيفشل بوضوح (exit 1) بدل ما يعدّل حاجة غلط بصمت — وده مقصود.

ملحوظة: الملف ده بيتنفذ مرة واحدة بس وقت الـ bootstrap، والنتيجة (بعد
التعديل) هي اللي بتتـcommit للريبو بشكل دائم. مش جزء من كل build عادي.
"""
import sys
import re
from pathlib import Path

GROOVY_PATH = Path("android/app/build.gradle")
KTS_PATH = Path("android/app/build.gradle.kts")

GROOVY_KEYSTORE_LOADER = '''
def keystorePropertiesFile = rootProject.file("key.properties")
def keystoreProperties = new Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
'''

GROOVY_SIGNING_CONFIGS = '''    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                storeFile file(keystoreProperties["storeFile"])
                storePassword keystoreProperties["storePassword"]
                keyAlias keystoreProperties["keyAlias"]
                keyPassword keystoreProperties["keyPassword"]
            }
        }
    }
'''

KTS_KEYSTORE_LOADER = '''
import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
'''

KTS_SIGNING_CONFIGS = '''    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }
'''


def patch_groovy(text: str) -> str:
    if re.search(r"signingConfigs\s*\{", text):
        raise SystemExit(
            "❌ build.gradle عنده signingConfigs بالفعل — السكريبت ده مصمم "
            "يتشغل مرة واحدة بس على ملف Flutter الافتراضي. توقفت بدل ما "
            "أعدّل حاجة موجودة بالفعل بصمت."
        )

    # 1) حط الـ keystore loader في أول الملف
    text = GROOVY_KEYSTORE_LOADER.strip("\n") + "\n\n" + text

    # 2) دور على "android {" وحط signingConfigs بعدها مباشرة
    android_block = re.search(r"android\s*\{", text)
    if not android_block:
        raise SystemExit("❌ مش لاقي 'android {' في build.gradle — الشكل غير متوقع.")
    insert_at = android_block.end()
    text = text[:insert_at] + "\n" + GROOVY_SIGNING_CONFIGS + text[insert_at:]

    # 3) استبدل "signingConfig signingConfigs.debug" جوه buildTypes.release
    #    بـ "signingConfig signingConfigs.release"
    pattern = re.compile(
        r"(release\s*\{[^}]*?)signingConfig\s+signingConfigs\.debug",
        re.DOTALL,
    )
    new_text, count = pattern.subn(r"\1signingConfig signingConfigs.release", text)
    if count == 0:
        raise SystemExit(
            "❌ مش لاقي 'signingConfig signingConfigs.debug' جوه buildTypes.release "
            "— الشكل الافتراضي اتغيّر، محتاج مراجعة يدوية."
        )
    return new_text


def patch_kts(text: str) -> str:
    if re.search(r"signingConfigs\s*\{", text):
        raise SystemExit(
            "❌ build.gradle.kts عنده signingConfigs بالفعل — توقفت بدل ما "
            "أعدّل حاجة موجودة بصمت."
        )

    text = KTS_KEYSTORE_LOADER.strip("\n") + "\n\n" + text

    android_block = re.search(r"android\s*\{", text)
    if not android_block:
        raise SystemExit("❌ مش لاقي 'android {' في build.gradle.kts.")
    insert_at = android_block.end()
    text = text[:insert_at] + "\n" + KTS_SIGNING_CONFIGS + text[insert_at:]

    # Flutter 3.44+ بيكتب: signingConfig = signingConfigs.debug
    # Flutter أقدم: signingConfig = signingConfigs.getByName("debug")
    pattern_new = re.compile(
        r'(release\s*\{[^}]*?)signingConfig\s*=\s*signingConfigs\.debug',
        re.DOTALL,
    )
    pattern_old = re.compile(
        r'(getByName\("release"\)\s*\{[^}]*?)signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        re.DOTALL,
    )
    new_text, count = pattern_new.subn(
        r'\1signingConfig = signingConfigs.getByName("release")', text
    )
    if count == 0:
        new_text, count = pattern_old.subn(
            r'\1signingConfig = signingConfigs.getByName("release")', text
        )
    if count == 0:
        # مفيش signingConfig line — نضيفها جوه release block
        new_text, count = re.subn(
            r'(release\s*\{)',
            r'\1\n            signingConfig = signingConfigs.getByName("release")',
            text,
            flags=re.DOTALL,
        )
        if count == 0:
            raise SystemExit(
                "❌ مش لاقي release block في buildTypes جوه build.gradle.kts "
                "— الشكل الافتراضي اتغيّر كتير، محتاج مراجعة يدوية."
            )
    return new_text


def main() -> None:
    if GROOVY_PATH.exists():
        target = GROOVY_PATH
        patched = patch_groovy(target.read_text())
    elif KTS_PATH.exists():
        target = KTS_PATH
        patched = patch_kts(target.read_text())
    else:
        raise SystemExit("❌ مفيش android/app/build.gradle ولا build.gradle.kts.")

    target.write_text(patched)
    print(f"✅ تم تحديث {target} — signingConfigs.release مضافة، "
          f"buildTypes.release بقى بيستخدمها بدل signingConfigs.debug.")


if __name__ == "__main__":
    main()
