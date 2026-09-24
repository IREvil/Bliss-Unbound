import unittest

from validate import apply_overrides


class ApplyOverridesTests(unittest.TestCase):
    def test_false_undefines_active_toggle(self):
        source = "#define GENERATED_NORMALS\n#ifdef GENERATED_NORMALS\nactive\n#endif\n"
        expected = "#undef GENERATED_NORMALS\n#ifdef GENERATED_NORMALS\nactive\n#endif\n"
        self.assertEqual(apply_overrides(source, {"GENERATED_NORMALS": "false"}), expected)

    def test_false_keeps_commented_toggle_disabled(self):
        source = "// #define DEFERRED_SPECULAR\n"
        self.assertEqual(
            apply_overrides(source, {"DEFERRED_SPECULAR": "false"}),
            "#undef DEFERRED_SPECULAR\n",
        )

    def test_true_enables_commented_toggle(self):
        source = "// #define DEFERRED_SPECULAR\n"
        self.assertEqual(
            apply_overrides(source, {"DEFERRED_SPECULAR": "true"}),
            "#define DEFERRED_SPECULAR\n",
        )

    def test_numeric_zero_remains_defined(self):
        source = "#define IPBR_MODE 1 // [0 1]\n"
        self.assertEqual(apply_overrides(source, {"IPBR_MODE": "0"}), "#define IPBR_MODE 0\n")

    def test_override_does_not_match_longer_name(self):
        source = "#define GENERATED_NORMALS_EXTRA\n"
        self.assertEqual(apply_overrides(source, {"GENERATED_NORMALS": "false"}), source)


if __name__ == "__main__":
    unittest.main()