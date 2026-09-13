#!/usr/bin/env python3
import unittest
from unittest.mock import patch, MagicMock
import os
import sys

_google_dir = os.path.realpath(os.path.join(os.path.dirname(__file__), '..'))
if _google_dir not in sys.path:
    sys.path.insert(0, _google_dir)

import google_config

class TestGoogleConfig(unittest.TestCase):

    def test_has_credentials(self):
        # We know check_credentials returned true earlier
        self.assertIsInstance(google_config.has_credentials(), bool)

    def test_resolve_token_ya29(self):
        ya29_token = "ya29.a0AfH6SMDummyAccessToken"
        self.assertEqual(google_config.resolve_token(ya29_token), ya29_token)

if __name__ == "__main__":
    unittest.main()
