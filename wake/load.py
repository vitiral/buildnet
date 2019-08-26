# ⏾🌊🛠 wake software's true potential
#
# Copyright (C) 2019 Rett Berg <github.com/vitiral>
#
# The source code is Licensed under either of
#
# * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#   http://www.apache.org/licenses/LICENSE-2.0)
# * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#   http://opensource.org/licenses/MIT)
#
# at your option.
#
# Unless you explicitly state otherwise, any contribution intentionally submitted
# for inclusion in the work by you, as defined in the Apache-2.0 license, shall
# be dual licensed as above, without any additional terms or conditions.
"""Load packages in various states."""

import os
import hashlib
import json

import six

from .constants import *
from . import utils
from . import pkg
from . import digest


def loadPkgDigest(state, pkg_file):
    """Load a package digest, returning PkgDigest.

    Note: The `state` is used to create a temporary directory for storing the
    custom-created jsonnet running script.
    """
    pkg_dir = os.path.dirname(pkg_file)
    digest_path = os.path.join(pkg_dir, DEFAULT_FILE_DIGEST)
    run_digest_text = utils.format_run_digest(pkg_file)

    state_dir = state.create_temp_dir()
    try:
        # Dump fake `.digest.json`
        utils.jsondumpf(digest_path, digest.Digest.fake().serialize())

        # Put the jsonnet run file in place
        run_digest_path = os.path.join(state_dir.dir, FILE_RUN_DIGEST)
        utils.dumpf(run_digest_path, run_digest_text)

        # Get a pkgDigest with the wrong digest value
        pkgDigest = pkg.PkgDigest.deserialize(
            utils.manifest_jsonnet(run_digest_path),
            pkg_file=pkg_file,
        )

        # Dump real `.digest.json`
        digest_value = digest.calc_digest(pkgDigest)
        utils.jsondumpf(digest_path, digest_value.serialize())

        pkgDigest = pkg.PkgDigest.deserialize(
            utils.manifest_jsonnet(run_digest_path),
            pkg_file=pkg_file,
        )

        assert pkgDigest.pkgVer.digest == digest_value
        return pkgDigest
    finally:
        if os.path.exists(digest_path):
            os.remove(digest_path)
        state_dir.cleanup()


def loadPkgExport(state, pkgsDefined, pkgDigest):
    """Load the exports of the package.

    Params:
    State state: used to create a temporary directory for storing the
        custom-created jsonnet running script.
    storeMap: dictionary of the expected lookup keys to the location of their PKG files.
    """
    pkg_dir = os.path.dirname(pkgDigest.pkg_file)
    digest_path = os.path.join(pkg_dir, DEFAULT_FILE_DIGEST)

    state_dir = state.create_temp_dir()
    try:
        pkgs_defined_path = _dump_pkgs_defined(
            state_dir.dir,
            pkgsDefined=pkgsDefined,
        )
        run_export_text = utils.format_run_export(
            pkgDigest.pkg_file,
            pkgs_defined_path=pkgs_defined_path,
        )
        run_export_path = os.path.join(state_dir.dir, FILE_RUN_DIGEST)

        # Dump real `.digest.json`
        utils.jsondumpf(digest_path, pkgDigest.pkgVer.digest.serialize())

        # Put the jsonnet run file in place
        utils.dumpf(run_export_path, run_export_text)

        # Run the export (includes depenencies) and get result
        pkgExport = utils.manifest_jsonnet(run_export_path)

        return pkgExport
    finally:
        if os.path.exists(digest_path):
            os.remove(digest_path)
        state_dir.cleanup()


def _dump_pkgs_defined(directory, pkgsDefined):
    """Dump all the defined pkgs into a jsonnet file.

    This allows them to be looked up by key.
    """
    pkgs_defined_path = os.path.join(directory, "pkgsDefined.libsonnet")
    with open(pkgs_defined_path, 'w') as fd:
        fd.write("{\n")
        for key, path in sorted(six.iteritems(pkgsDefined)):
            key, path = json.dumps(key), json.dumps(path)
            fd.write("  {}: (import {}),\n\n".format(key, path))
        fd.write("}\n")

        utils.closefd(fd)

    return pkgs_defined_path
