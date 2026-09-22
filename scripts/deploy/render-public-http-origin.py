#!/usr/bin/env python3
"""Render the deployment's public-HTTP opt-in into a browser bundle.

The console, workbench and enterprise pages ship an empty
`lunanexa-public-http-origin` meta element, so public plain HTTP stays
disabled by default. A deployment that chooses temporary HTTP over TLS must
set that element to the page's own exact origin; `ui/browser_transport` then
accepts credentials only when the configured origin, the page origin and the
API origin all agree.

This is deliberately a separate step rather than a committed value: the origin
belongs to the deployment, not to the source tree, and a wrong origin fails
closed (the page refuses to hand a credential to the app) rather than open.

Usage:

    python3 scripts/deploy/render-public-http-origin.py \
        --dist _build/browser-dist \
        --origin console=http://106.39.18.146:4174 \
        --origin enterprise=http://106.39.18.146:5002

Each `--origin` names a directory under the dist root and the origin that
page is served from. Pages not named keep their empty meta, which keeps them
disabled on public HTTP.
"""

import argparse
import os
import re
import sys
from urllib.parse import urlsplit

META = re.compile(
    r'(<meta\s+name="lunanexa-public-http-origin"\s+content=")([^"]*)(")'
)

OPEN_META = re.compile(
    r'(<meta\s+name="lunanexa-operator-open"\s+content=")([^"]*)(")'
)


def checked_origin(value):
    """An exact origin: scheme, host, optional port. No path, query or fragment."""
    parts = urlsplit(value)
    if parts.scheme not in ("http", "https"):
        raise ValueError("origin must be http or https: %s" % value)
    if not parts.netloc or parts.username or parts.password:
        raise ValueError("origin must name a host: %s" % value)
    if parts.path not in ("", "/") or parts.query or parts.fragment:
        raise ValueError("origin must not carry a path or parameters: %s" % value)
    return "%s://%s" % (parts.scheme, parts.netloc)


def checked_open_value(value):
    """`*` or an exact origin.

    The console skips its login gate when this value matches the page origin,
    and the same-origin proxy then attaches operator authority to every API
    call. `*` therefore means "anyone who can reach this page is the operator",
    which is a deployment decision, not a default -- the committed meta is empty
    and this script is the only thing that fills it in.
    """
    if value == "*":
        return value
    return checked_origin(value)


def render_open(dist, page, value):
    path = os.path.join(dist, page, "index.html")
    if not os.path.isfile(path):
        raise SystemExit("no page at %s" % path)
    with open(path, encoding="utf-8") as handle:
        body = handle.read()
    if not OPEN_META.search(body):
        raise SystemExit(
            "%s has no lunanexa-operator-open meta; the page cannot be opened "
            "without a login" % path
        )
    body = OPEN_META.sub(
        lambda match: match.group(1) + value + match.group(3), body, count=1
    )
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)
    print("opened %s as %s" % (path, value))


def render(dist, page, origin):
    path = os.path.join(dist, page, "index.html")
    if not os.path.isfile(path):
        raise SystemExit("no page at %s" % path)
    with open(path, encoding="utf-8") as handle:
        body = handle.read()
    if not META.search(body):
        raise SystemExit(
            "%s has no lunanexa-public-http-origin meta; the page cannot be "
            "opted into public HTTP" % path
        )
    body = META.sub(lambda match: match.group(1) + origin + match.group(3), body, count=1)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)
    print("rendered %s as %s" % (path, origin))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist", required=True, help="browser bundle root")
    parser.add_argument(
        "--origin",
        action="append",
        default=[],
        metavar="PAGE=ORIGIN",
        help="page directory and the exact origin it is served from",
    )
    parser.add_argument(
        "--operator-open",
        action="append",
        default=[],
        metavar="PAGE=*|ORIGIN",
        help=(
            "page directory that skips its login gate; the same-origin proxy "
            "then attaches operator authority. `*` accepts any origin that can "
            "reach the page, which makes the page operator-authenticated for "
            "everyone who can load it"
        ),
    )
    arguments = parser.parse_args()
    if not arguments.origin and not arguments.operator_open:
        sys.exit("no --origin or --operator-open given; nothing to render")
    for entry in arguments.origin:
        page, separator, origin = entry.partition("=")
        if not separator or not page or not origin:
            sys.exit("--origin expects PAGE=ORIGIN, got %s" % entry)
        try:
            rendered = checked_origin(origin)
        except ValueError as error:
            sys.exit(str(error))
        render(arguments.dist, page, rendered)
    for entry in arguments.operator_open:
        page, separator, value = entry.partition("=")
        if not separator or not page or not value:
            sys.exit("--operator-open expects PAGE=*|ORIGIN, got %s" % entry)
        try:
            rendered = checked_open_value(value)
        except ValueError as error:
            sys.exit(str(error))
        render_open(arguments.dist, page, rendered)


if __name__ == "__main__":
    main()
