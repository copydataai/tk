import json, os, pathlib, plistlib, subprocess, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class QualificationCLITests(unittest.TestCase):
    def test_installed_qualification_requires_the_exact_dmg_and_checksum(self):
        result=subprocess.run([str(ROOT/"script/qualify_installed_app.sh"),"/does/not/exist.dmg"],text=True,capture_output=True)
        self.assertEqual(result.returncode,2)
        self.assertIn("DMG and matching .sha256 required",result.stderr)

    def test_installed_qualification_declares_all_required_predicates(self):
        source=(ROOT/"script/qualify_installed_app.sh").read_text()
        for predicate in ("hdiutil attach","spctl --assess","codesign --verify","stapler validate","TK_QUALIFICATION_READY_FILE","runtimeDownloadsRequired","residentListener","sbom.json","provenance.json","rollback.json","uninstall.json","qualify_compatibility.py"):
            self.assertIn(predicate,source)

    def test_writer_accepts_normal_app_bundle_and_derives_context(self):
        with tempfile.TemporaryDirectory() as raw:
            root=pathlib.Path(raw); app=root/"tk.app"; (app/"Contents").mkdir(parents=True)
            plistlib.dump({"CFBundleShortVersionString":"1.2.3","CFBundleVersion":"45"},open(app/"Contents/Info.plist","wb"))
            dmg=root/"tk-1.2.3.dmg"; dmg.write_bytes(b"immutable")
            bindir=root/"bin"; bindir.mkdir()
            for name,value in (("sw_vers","24A123"),("sysctl","Mac15,6")):
                path=bindir/name; path.write_text(f"#!/bin/sh\necho {value}\n"); path.chmod(0o700)
            out=root/"evidence"; env=os.environ|{"PATH":f"{bindir}:{os.environ['PATH']}"}
            command=[str(ROOT/"script/record_continuity_evidence.py"),"--row","exact-row","--dmg",str(dmg),"--app",str(app),"--device-uid","uid-1","--input-route","Built-in","--sample-rate","48000","--phase","recording","--notification","observed","--outcome","Pass","--audio-disposition","removed","--helper-disposition","stopped","--assertion","physically observed","--output-dir",str(out),"--physical"]
            result=subprocess.run(command,text=True,capture_output=True,env=env,check=True)
            record=json.load(open(result.stdout.strip()))
            self.assertEqual((record["appVersion"],record["appBuild"],record["macOSBuild"],record["hardwareIdentifier"]),("1.2.3","45","24A123","Mac15,6"))

    def test_gate_rejects_future_malformed_and_unlinked_evidence(self):
        with tempfile.TemporaryDirectory() as raw:
            root=pathlib.Path(raw); records=root/"records"; records.mkdir(); (records/"future.json").write_text('{"schemaVersion":2}')
            matrix=root/"matrix.md"; matrix.write_text("## Exact\n| Target | Status | Record |\n| --- | --- | --- |\n| one | Pass | [record](missing.json) |\n")
            result=subprocess.run([str(ROOT/"script/qualify_compatibility.py"),"--matrix",str(matrix),"--records",str(records)],text=True,capture_output=True)
            self.assertNotEqual(result.returncode,0)
            report=json.loads(result.stdout)
            self.assertTrue(any("linked record missing" in item for item in report["failures"]))
            self.assertTrue(any("unlinked evidence" in item for item in report["failures"]))

if __name__ == "__main__": unittest.main()
