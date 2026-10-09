"""Exercise quality gates with valid and invalid input."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


commits = load("check_commits")
coverage = load("check_coverage")


class CommitTests(unittest.TestCase):
    def test_conventional_subjects(self):
        for message in ("feat: add peeks", "fix(worker): handle probe errors",
                        "refactor(core)!: change geometry\n\nBREAKING CHANGE: changed API"):
            with self.subTest(message=message):
                self.assertTrue(commits.validate(message))

    def test_rejects_invalid_subjects(self):
        for message in ("", "update things", "Fix: badge", "fix:", "fix: ",
                        "fix: badge ", "feat(): add", "feat: " + "a" * 67):
            with self.subTest(message=message):
                self.assertFalse(commits.validate(message))


class CoverageTests(unittest.TestCase):
    def report(self, covered=10):
        return {"data": [{"files": [
            {"filename": str(path.resolve()),
             "summary": {"lines": {"count": 10, "covered": covered}}}
            for path in (ROOT / "Sources/DockPeekCore").glob("*.swift")
        ]}]}

    def test_accepts_complete_coverage(self):
        coverage.check(self.report())

    def test_rejects_insufficient_coverage(self):
        with self.assertRaises(ValueError):
            coverage.check(self.report(9))

    def test_rejects_missing_source(self):
        report = self.report()
        report["data"][0]["files"].pop()
        with self.assertRaises(ValueError):
            coverage.check(report)

    def test_rejects_empty_report(self):
        with self.assertRaises(ValueError):
            coverage.check({"data": []})
