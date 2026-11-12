#!/usr/bin/env python3
"""35 deterministic source/UX-contract checks. These are NOT interactive XCUITests."""
import pathlib, re, unittest, json
R=pathlib.Path(__file__).resolve().parents[1]
def source(name):
    p=R/"Gifski"/name
    return p.read_text() if p.exists() else ""
class UXContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main=source("MainScreen.swift")
        cls.start=source("StartScreen.swift")
        cls.edit=source("EditScreen.swift")
        cls.settings=source("SettingsScreen.swift")
        cls.project=(R/"Gifski.xcodeproj/project.pbxproj").read_text()
    def assertInSource(self, token, s): self.assertIn(token,s)
    def test_01_main_screen_exists(self): self.assertTrue(self.main)
    def test_02_start_screen_exists(self): self.assertTrue(self.start)
    def test_03_edit_screen_exists(self): self.assertTrue(self.edit)
    def test_04_settings_screen_exists(self): self.assertTrue(self.settings)
    def test_05_navigation_stack(self): self.assertInSource("NavigationStack",self.main)
    def test_06_start_route(self): self.assertInSource("StartScreen()",self.main)
    def test_07_image_sequence_route(self): self.assertInSource("case .imageSequence(",self.main)
    def test_08_image_export_route(self): self.assertInSource("case .imageSequenceConversion(",self.main)
    def test_09_video_export_route(self): self.assertInSource("case .imageSequenceVideoConversion(",self.main)
    def test_10_completed_route(self): self.assertInSource("case .completed(",self.main)
    def test_11_window_min_width(self): self.assertRegex(self.main,r"minWidth:\s*700")
    def test_12_window_min_height(self): self.assertRegex(self.main,r"minHeight:\s*600")
    def test_13_file_importer(self): self.assertInSource(".fileImporter(",self.main)
    def test_14_multiple_selection(self): self.assertInSource("allowsMultipleSelection: true",self.main)
    def test_15_image_import_type(self): self.assertInSource(".image",self.main)
    def test_16_import_error_handling(self): self.assertInSource("appState.error = error",self.main)
    def test_17_import_accessible_description(self): self.assertInSource("Choose a video or two or more still images",self.main)
    def test_18_drop_delegate(self): self.assertInSource(".onDrop(",self.main)
    def test_19_drop_validation(self): self.assertInSource("onValidate:",self.main)
    def test_20_drop_visual_feedback(self): self.assertInSource("isDropTargeted",self.main)
    def test_21_drop_disabled_during_conversion(self): self.assertInSource("appState.isConverting",self.main)
    def test_22_start_splash(self): self.assertInSource('Image("GifInStillsSplash")',self.start)
    def test_23_splash_resizable(self): self.assertInSource(".resizable()",self.start)
    def test_24_splash_clipped(self): self.assertInSource(".clipped()",self.start)
    def test_25_splash_accessible_import_button(self): self.assertInSource('Button("Choose Files…"',self.start)
    def test_26_start_progress(self): self.assertInSource("ProgressView",self.start)
    def test_27_start_help_text(self): self.assertInSource("Drop images or a video",self.start)
    def test_28_start_scaling(self): self.assertInSource("proxy.size.width",self.start)
    def test_29_start_contrast_material(self): self.assertInSource(".ultraThinMaterial",self.start)
    def test_30_edit_preview(self): self.assertInSource("trimmingAVPlayer",self.edit)
    def test_31_edit_controls(self): self.assertInSource("controls",self.edit)
    def test_32_edit_navigation_title(self): self.assertInSource(".navigationTitle(",self.edit)
    def test_33_edit_export(self): self.assertInSource("ExportModifiedVideoView",self.edit)
    def test_34_settings_downloads(self): self.assertInSource("Automatically save GIFs to Downloads",self.settings)
    def test_35_raster_splash_asset(self):
        p=R/"Gifski/Assets.xcassets/GifInStillsSplash.imageset"
        j=json.loads((p/"Contents.json").read_text())
        self.assertEqual(j["images"][0]["filename"],"GifInStillsSplash.png")
        self.assertTrue((p/"GifInStillsSplash.png").is_file())
if __name__=="__main__": unittest.main(verbosity=2)
