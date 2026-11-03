"""Build a signed test APK without Gradle or third-party libraries.
Uses Android SDK Build-Tools 34, platform 34 and JDK 17+.
Set JAVA_HOME, ANDROID_BUILD_TOOLS and ANDROID_JAR to override local tools.
The testing signing key is retained locally, never included in the source ZIP.
"""
from pathlib import Path
import os,subprocess,tempfile,shutil,zipfile,hashlib,json
r=Path(__file__).resolve().parent
jdk=Path(os.environ.get('JAVA_HOME',r'D:/JetBrains/PyCharm 2025.1.3.1/jbr'))
bt=Path(os.environ.get('ANDROID_BUILD_TOOLS',str(r.parent/'tmp/android_sdk/buildtools/android-14')))
jar=Path(os.environ.get('ANDROID_JAR',str(r.parent/'tmp/android_sdk/platform/android-34/android.jar')))
stage=Path(tempfile.mkdtemp(prefix='acg525_apk_'))
for d in ['src','assets','res']:shutil.copytree(r/d,stage/d)
shutil.copy2(r/'AndroidManifest.xml',stage/'AndroidManifest.xml')
logs=[]
def run(args):
 p=subprocess.run([str(x) for x in args],cwd=stage,capture_output=True,text=True,encoding='utf-8',errors='replace')
 logs.append(p.stdout+p.stderr)
 if p.returncode:
  (r/'build.log').write_text('\n'.join(logs),encoding='utf-8');raise SystemExit(p.stdout+p.stderr)
 return p.stdout+p.stderr
run([bt/'aapt2.exe','compile','--dir',stage/'res','-o',stage/'resources.zip'])
run([bt/'aapt2.exe','link','-o',stage/'base.apk','--manifest',stage/'AndroidManifest.xml','-I',jar,'-A',stage/'assets',stage/'resources.zip'])
(stage/'classes').mkdir();(stage/'dex').mkdir()
javac=Path(os.environ.get('JAVAC',r'C:/Program Files/Android/jdk/jdk-8.0.302.8-hotspot/jdk8u302-b08/bin/javac.exe'))
run([javac,'-encoding','UTF-8','-source','8','-target','8','-classpath',jar,'-d',stage/'classes',*sorted((stage/'src').rglob('*.java'))])
with zipfile.ZipFile(stage/'classes.jar','w') as z:
 for p in (stage/'classes').rglob('*.class'):z.write(p,p.relative_to(stage/'classes'))
run([jdk/'bin/java.exe','-cp',bt/'lib/d8.jar','com.android.tools.r8.D8','--lib',jar,'--min-api','23','--output',stage/'dex',stage/'classes.jar'])
with zipfile.ZipFile(stage/'base.apk','a',zipfile.ZIP_DEFLATED) as z:
 for p in (stage/'dex').glob('*.dex'):z.write(p,p.name)
run([bt/'zipalign.exe','-f','4',stage/'base.apk',stage/'aligned.apk'])
key=r/'.local-signing/test.jks';key.parent.mkdir(exist_ok=True)
if not key.exists():run([jdk/'bin/keytool.exe','-genkeypair','-keystore',key,'-storepass','android','-keypass','android','-alias','acg525-test','-keyalg','RSA','-keysize','2048','-validity','10000','-dname','CN=ACG525 Local Test'])
out=r/'ACG525_MusicCoach_2.2_reconstruction.apk'
run([jdk/'bin/java.exe','-jar',bt/'lib/apksigner.jar','sign','--ks',key,'--ks-key-alias','acg525-test','--ks-pass','pass:android','--key-pass','pass:android','--out',out,stage/'aligned.apk'])
verify=run([jdk/'bin/java.exe','-jar',bt/'lib/apksigner.jar','verify','--verbose','--print-certs',out])
badging=run([bt/'aapt2.exe','dump','badging',out]);print(verify);print(badging)
assert "package: name='cn.acg525.musiccoach'" in badging
assert 'android.permission.INTERNET' not in badging
(r/'build.log').write_text('\n'.join(logs),encoding='utf-8')
(r/'BUILD_INFO.json').write_text(json.dumps({'stage':str(stage),'apk':out.name,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'bytes':out.stat().st_size,'compile_sdk':34,'min_sdk':23,'target_sdk':34,'signing':'local testing RSA key; not an app-store release'},indent=2))
print('PASS signed APK: '+str(out))

