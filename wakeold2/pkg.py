# -*- coding: utf-8 -*-
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
"""Pkg types."""
from __future__ import unicode_literals

import os

from . import constants
from . import utils
from . import digest


class PkgName(utils.TupleObject):
    """The namespace and name of a package."""
    def __init__(self, namespace, name):
        self.namespace = namespace
        self.name = name

    def __str__(self):
        return constants.WAKE_SEP.join((self.namespace, self.name))

    def __repr__(self):
        return "name:{}".format(self)

    def _tuple(self):
        return (self.namespace, self.name)


class PkgReq(utils.TupleObject):
    """A semver requirement for a package.

    Used to specify a dependency.
    """
    def __init__(self, namespace, name, semver):
        self.namespace = namespace
        self.name = name
        self.semver = semver

    @classmethod
    def deserialize(cls, string):
        """Deserialize."""
        split = string.split(constants.WAKE_SEP)
        if len(split) > 3:
            raise ValueError("Must have 3 components split by {}: {}".format(
                constants.WAKE_SEP, string))

        namespace, name, semver = split
        return cls(namespace=namespace, name=name, semver=semver)

    def serialize(self):
        """Serialize."""
        return constants.WAKE_SEP.join(self._tuple())

    def __str__(self):
        return self.serialize()

    def __repr__(self):
        return "req:{}".format(self)

    def _tuple(self):
        return (self.namespace, self.name, self.semver)


class PkgRequest(utils.TupleObject):
    """A request from a package for a package requirement semver.

    Used as a key in jsonnet when associating dependencies.
    """
    def __init__(self, requestingPkgVer, pkgReq):
        self.requestingPkgVer = requestingPkgVer
        self.pkgReq = pkgReq

    def serialize(self):
        return constants.WAKE_SEP.join((
            self.requestingPkgVer.serialize(),
            self.pkgReq.serialize(),
        ))

    def __str__(self):
        return self.serialize()

    def __repr__(self):
        return "pkgRequest:{}".format(self)

    def _tuple(self):
        return (self.requestingPkgVer, self.pkgReq)


class PkgVer(utils.TupleObject):
    """A pkg at a specific version and hashed digest."""

    # pylint: disable=redefined-outer-name
    def __init__(self, namespace, name, version, digest):
        self.namespace = namespace
        self.name = name
        self.version = version
        self.digest = digest

    @classmethod
    def deserialize(cls, string):
        """Deserialize."""
        split = string.split(constants.WAKE_SEP)
        if len(split) > 4:
            raise ValueError("Must have 4 components split by {}: {}".format(
                constants.WAKE_SEP, string))

        namespace, name, version, digest_str = split
        return cls(
            namespace=namespace,
            name=name,
            version=version,
            digest=digest.Digest.deserialize(digest_str),
        )

    def serialize(self):
        """Serialize."""
        return constants.WAKE_SEP.join((
            self.namespace,
            self.name,
            self.version,
            self.digest.serialize(),
        ))

    def __str__(self):
        return self.serialize()

    def __repr__(self):
        return "ver:{}".format(self)

    def _tuple(self):
        return (self.namespace, self.name, self.version, self.digest)


class PkgDeclared(utils.SafeObject):
    """The items which are used in the pkg digest.

    These items must completely define the package for transport and use.
    """

    # pylint: disable=too-many-arguments
    def __init__(self, pkg_file, pkgVer, pkgOrigin, paths, depsReq):
        if pkg_file not in paths:
            paths.add('./' + constants.FILE_PKG_DEFAULT)

        self.pkg_file = pkg_file
        self.pkg_dir = os.path.dirname(pkg_file)
        self.pkg_digest = os.path.join(self.pkg_dir,
                                       constants.DEFAULT_FILE_DIGEST)
        self.pkgVer = pkgVer
        self.pkgOrigin = pkgOrigin
        self.paths = paths
        self.depsReq = depsReq

    @classmethod
    def deserialize(cls, dct, pkg_file):
        """Derialize."""
        pkg_ver_str = utils.ensure_str('pkgVer', dct['pkgVer'])
        return cls(
            pkg_file=pkg_file,
            pkgVer=PkgVer.deserialize(pkg_ver_str),
            pkgOrigin=dct.get('pkgOrigin'),
            paths=set(utils.ensure_valid_paths(dct['paths'])),
            depsReq=dct['depsReq'],
        )

    def serialize(self):
        """Serialize."""
        pfile = os.path.basename(self.pkg_file)
        return {
            "pkg_file": pfile,
            "pkgVer": self.pkgVer.serialize(),
            "pkgOrigin": self.pkgOrigin,
            "paths": sorted(self.paths),
            "depsReq": self.depsReq,
        }

    def __repr__(self):
        return 'PkgDeclared{}'.format(self.serialize())


class PkgExport(PkgDeclared):
    """Pkg with self.export and depdency's export fields resolved."""

    # pylint: disable=too-many-arguments
    def __init__(self, pkg_file, pkgVer, pkgOrigin, paths, depsReq, deps,
                 export):
        super(PkgExport, self).__init__(
            pkg_file=pkg_file,
            pkgVer=pkgVer,
            pkgOrigin=pkgOrigin,
            paths=paths,
            depsReq=depsReq,
        )

        self.deps = deps
        self.export = export

    @classmethod
    def deserialize(cls, dct, pkg_file):
        dig = PkgDeclared.deserialize(dct, pkg_file)
        return cls(
            pkg_file=dig.pkg_file,
            pkgVer=dig.pkgVer,
            pkgOrigin=dig.pkgOrigin,
            paths=dig.paths,
            depsReq=dig.depsReq,
            deps=dct['deps'],
            export=dct['export'],
        )

    def serialize(self):
        dct = super(PkgExport, self).serialize()
        dct['deps'] = self.deps
        dct['export'] = self.export
        return dct
