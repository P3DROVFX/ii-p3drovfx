#!/usr/bin/env python3
"""The web fetch tool must stay on the public internet.

`fetch` is the one tool whose argument the model chooses freely, so it is also
the one an attacker reaches by writing on a page the model reads. These tests
pin the two halves of the defence: which addresses count as reachable, and the
fact that every redirect hop is checked rather than only the first URL.

Nothing here touches the network. Name resolution is stubbed, so the suite is
the same on a laptop with no connection as it is in CI.
"""

import importlib.util
import io
import socket
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
WEB_PATH = ROOT / "scripts" / "ai" / "ai_web.py"
WEB_SPEC = importlib.util.spec_from_file_location("ai_web", WEB_PATH)
WEB = importlib.util.module_from_spec(WEB_SPEC)
WEB_SPEC.loader.exec_module(WEB)
WEB_SOURCE = WEB_PATH.read_text(encoding="utf-8")


def resolve_to(*addresses):
    """A getaddrinfo that answers with the addresses given, by name."""

    def fake(host, port, *args, **kwargs):
        answers = addresses if not isinstance(addresses[0], dict) else addresses[0].get(host, [])
        if not answers:
            raise socket.gaierror("name or service not known")
        return [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", (address, port))
                for address in answers]

    return fake


class AddressClassificationTests(unittest.TestCase):
    def test_public_addresses_are_reachable(self):
        for address in ("8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:4700::1111"):
            with self.subTest(address=address):
                self.assertTrue(WEB.address_is_reachable(address))

    def test_local_and_private_addresses_are_refused(self):
        blocked = (
            "127.0.0.1",        # the shell's own Ollama lives here
            "127.0.0.53",
            "0.0.0.0",
            "10.1.2.3",
            "172.16.9.9",
            "192.168.1.1",      # the router's admin page
            "169.254.169.254",  # cloud metadata
            "100.64.0.7",       # CGNAT, which is where Tailscale sits
            "198.18.0.1",
            "::1",
            "fc00::1",
            "fe80::1",
            "::ffff:127.0.0.1",  # a v4 loopback smuggled inside a v6 literal
            "224.0.0.1",
            "240.0.0.1",
        )
        for address in blocked:
            with self.subTest(address=address):
                self.assertFalse(WEB.address_is_reachable(address))

    def test_nonsense_is_not_reachable(self):
        for address in ("", "not-an-address", "999.999.999.999"):
            with self.subTest(address=address):
                self.assertFalse(WEB.address_is_reachable(address))


class TargetCheckTests(unittest.TestCase):
    def test_only_http_schemes_pass(self):
        for url in ("file:///etc/passwd", "ftp://example.com/x", "gopher://example.com",
                    "data:text/html,hi", "javascript:alert(1)"):
            with self.subTest(url=url):
                with self.assertRaises(WEB.BlockedTarget):
                    WEB.check_target(url)

    def test_public_host_passes(self):
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34")):
            host, port = WEB.check_target("https://example.com/page")
        self.assertEqual(host, "example.com")
        self.assertEqual(port, 443)

    def test_hostname_resolving_to_loopback_is_refused(self):
        # A public name pointing at 127.0.0.1 is the standard way past a check
        # that only looks at the literal in the URL.
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("127.0.0.1")):
            with self.assertRaises(WEB.BlockedTarget):
                WEB.check_target("http://localtest.example/")

    def test_one_private_answer_among_public_ones_is_refused(self):
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34", "10.0.0.1")):
            with self.assertRaises(WEB.BlockedTarget):
                WEB.check_target("http://split.example/")

    def test_unresolvable_host_is_refused(self):
        def fail(*args, **kwargs):
            raise socket.gaierror("nope")

        with mock.patch.object(WEB.socket, "getaddrinfo", fail):
            with self.assertRaises(WEB.BlockedTarget):
                WEB.check_target("http://nowhere.example/")

    def test_explicit_port_is_carried_through(self):
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34")):
            _, port = WEB.check_target("http://example.com:8080/")
        self.assertEqual(port, 8080)


class RedirectTests(unittest.TestCase):
    """A hop is only safe if the hop itself was checked."""

    def redirecting_opener(self, location, code=302):
        opener = mock.Mock()

        def open_once(request, timeout=None):
            raise urllib.error.HTTPError(
                request.full_url, code, "Found",
                {"Location": location}, io.BytesIO(b""))

        opener.open.side_effect = open_once
        return opener

    def test_redirect_into_the_private_network_is_refused(self):
        hosts = {"public.example": ["93.184.216.34"], "internal.example": ["192.168.0.10"]}
        opener = self.redirecting_opener("http://internal.example/admin")
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to(hosts)), \
             mock.patch.object(WEB.urllib.request, "build_opener", return_value=opener):
            result = WEB.fetch("http://public.example/start")
        self.assertTrue(result.get("blocked"))
        self.assertIn("192.168.0.10", result["error"])

    def test_redirect_to_a_non_http_scheme_is_refused(self):
        opener = self.redirecting_opener("file:///etc/shadow")
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34")), \
             mock.patch.object(WEB.urllib.request, "build_opener", return_value=opener):
            result = WEB.fetch("http://public.example/start")
        self.assertTrue(result.get("blocked"))

    def test_a_redirect_loop_ends(self):
        opener = self.redirecting_opener("http://public.example/start")
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34")), \
             mock.patch.object(WEB.urllib.request, "build_opener", return_value=opener):
            result = WEB.fetch("http://public.example/start")
        self.assertTrue(result.get("blocked"))
        self.assertIn("redirect", result["error"])
        self.assertLessEqual(opener.open.call_count, WEB.MAX_REDIRECTS + 1)


class FetchResultTests(unittest.TestCase):
    class Response:
        def __init__(self, body, content_type="text/html", url="http://public.example/start"):
            self.body = body
            self._url = url
            self.headers = self.Headers(content_type)

        class Headers:
            def __init__(self, content_type):
                self.content_type = content_type

            def get_content_type(self):
                return self.content_type

            def get_content_charset(self):
                return "utf-8"

        def read(self, size=-1):
            return self.body[:size] if size and size > 0 else self.body

        def geturl(self):
            return self._url

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    def opener_for(self, response):
        opener = mock.Mock()
        opener.open.return_value = response
        return opener

    def test_a_public_page_comes_back_as_text(self):
        page = b"<html><head><title>Hello</title></head><body><p>Body text</p></body></html>"
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34")), \
             mock.patch.object(WEB.urllib.request, "build_opener",
                               return_value=self.opener_for(self.Response(page))):
            result = WEB.fetch("http://public.example/start")
        self.assertNotIn("error", result)
        self.assertEqual(result["title"], "Hello")
        self.assertIn("Body text", result["text"])

    def test_a_binary_content_type_is_refused(self):
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34")), \
             mock.patch.object(WEB.urllib.request, "build_opener",
                               return_value=self.opener_for(
                                   self.Response(b"\x00\x01", "application/zip"))):
            result = WEB.fetch("http://public.example/archive.zip")
        self.assertTrue(result.get("blocked"))

    def test_an_oversized_page_is_cut_not_streamed_whole(self):
        page = b"<html><body>" + b"a" * (WEB.MAX_BYTES * 2) + b"</body></html>"
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("93.184.216.34")), \
             mock.patch.object(WEB.urllib.request, "build_opener",
                               return_value=self.opener_for(self.Response(page))):
            result = WEB.fetch("http://public.example/huge")
        self.assertLessEqual(len(result["text"]), WEB.MAX_TEXT)
        self.assertTrue(result["truncated"])

    def test_the_blocked_error_names_the_url_the_model_asked_for(self):
        with mock.patch.object(WEB.socket, "getaddrinfo", resolve_to("127.0.0.1")):
            result = WEB.fetch("http://localhost:11434/api/tags")
        self.assertTrue(result.get("blocked"))
        self.assertEqual(result["url"], "http://localhost:11434/api/tags")


class SourceContractTests(unittest.TestCase):
    """What must remain true of the file, so the guard cannot be walked around."""

    def test_fetch_goes_through_the_guarded_opener(self):
        body = WEB_SOURCE.split("def fetch(url: str) -> dict:", 1)[1].split("def main(", 1)[0]
        self.assertIn("open_guarded(url)", body)
        # `get()` is for the search backends, whose addresses come from the
        # user's configuration. It must not be how a model-chosen URL is read.
        self.assertNotIn("get(url)", body)

    def test_redirects_are_not_delegated_to_urllib(self):
        self.assertIn("class NoRedirect", WEB_SOURCE)
        guarded = WEB_SOURCE.split("def open_guarded", 1)[1].split("def fetch(", 1)[0]
        self.assertIn("check_target(seen)", guarded)
        self.assertIn("build_opener(NoRedirect)", guarded)


if __name__ == "__main__":
    unittest.main()
