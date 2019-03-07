#   Copyright 2019 Rett Berg (googberg@gmail.com)
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

from wakedev import *
from wakehash import *


class PkgKey(object):
    def __init__(self, namespace, name):
        self.namespace = namespace
        self.name = name

    def __hash__(self):
        return hash((self.namespace, self.name))

    def __str__(self):
        return WAKE_SEP.join((self.namespace, self.name))

    def __repr__(self):
        return "PkgKey({})".format(self)


class PkgReq(object):
    def __init__(self, namespace, name, version, hash_=None):
        self.namespace = namespace
        self.name = name
        self.version = version
        self.hash = hash_

    @classmethod
    def from_str(cls, s):
        spl = s.split(WAKE_SEP)
        namespace, name, version = spl[:3]
        if len(spl) > 4:
            raise ValueError(s)
        elif len(spl) == 4:
            hash_ = spl[3]
        else:
            hash_ = None

        return cls(namespace, name, version, hash_)

    def __str__(self):
        out = [
            self.namespace,
            self.name,
            self.version,
        ]
        if self.hash:
            out.append(self.hash)
        return WAKE_SEP.join(out)

    def __repr__(self):
        return "PkgReq({})".format(self)



class PkgManifest(object):
    """The result of "running" a pkg."""
    def __init__(self, root, all_pkgs):
        self.root = root
        self.all = all_pkgs


    @classmethod
    def from_dict(cls, dct):
        return cls(
            root=PkgSimple.from_dict(dct['root']),
            all_pkgs=[
                PkgUnresolved.from_dict(p) if is_unresolved(p)
                else PkgSimple.from_dict(p)
                for p in dct['all']
            ],
        )

    def to_dict(self):
        return {
            "root": self.root.to_dict(),
            "all": [p.to_dict() for p in self.all],
        }

class Fingerprint(object):
    def __init__(self, hash_, hash_type):
        self.hash = hash_
        self.hash_type = hash_type

    @classmethod
    def from_dict(cls, dct):
        return cls(
            hash_=dct['hash'],
            hash_type=dct['hash_type']
        )

    def to_dict(self):
        return {
            'hash': self.hash,
            'hashType': self.hash_type,
        }


class PkgSimple(object):
    """Pull out only the data we care about."""
    def __init__(self, state, pkg_id, namespace, name, version, fingerprint, paths, def_paths):
        hash_ = fingerprint['hash']
        expected_pkg_id = [namespace, name, version, hash_]
        assert expected_pkg_id == pkg_id.split(WAKE_SEP), (
            "pkgId != 'namespace#name#version#hash':\n{}\n{}".format(
                pkg_id, expected_pkg_id))

        assert_valid_paths(paths)
        assert_valid_paths(def_paths)

        self.state = state
        self.pkg_root = path.join("./", FILE_PKG)
        self.pkg_local_deps = path.join("./", DIR_WAKE, FILE_LOCAL_DEPENDENCIES)
        self.pkg_fingerprint = path.join("./", DIR_WAKE, FILE_FINGERPRINT)
        # TODO: pkg_id_str and pkg_id
        self.pkg_id = pkg_id
        self.namespace = namespace
        self.name = name
        self.version = version
        self.fingerprint = fingerprint

        self.paths = paths
        self.def_paths = def_paths

    def get_pkg_key(self):
        return PkgKey(self.namespace, self.name)

    def __repr__(self):
        return "{}(id={}, state={})".format(
            self.__class__.__name__,
            self.pkg_id,
            self.state
        )

    @classmethod
    def from_dict(cls, dct):
        assert is_pkg(dct)
        assert not is_unresolved(dct), "unresolved pkg: " + repr(dct)

        return cls(
            state=dct[F_STATE],
            pkg_id=dct['pkgId'],
            namespace=dct['namespace'],
            name=dct['name'],
            version=dct['version'],
            fingerprint=dct['fingerprint'],
            paths=dct['paths'],
            def_paths=dct['defPaths'],
        )

    def to_dict(self):
        # TODO: probably want all, only a few is good for repr for now
        return {
            F_STATE: self.state,
            'pkgId': self.pkg_id,
            'paths': self.paths,
            'defPaths': self.def_paths,
        }

    def get_def_fsentries(self):
        """Return all defined pkgs, including root."""
        default = [
            self.pkg_root,
            self.pkg_local_deps,
            self.pkg_fingerprint,
        ]
        return itertools.chain(default, self.def_paths)

    def get_fsentries(self):
        return itertools.chain(self.get_def_fsentries(), self.paths)

    def get_pkg_req(self):
        """Convert to just the pkg req key (no hash)."""

    def is_unresolved(self):
        return False


class PkgUnresolved(object):
    def __init__(self, pkg_req, from_, full):
        if isinstance(from_, str) and not from_.startswith('./'):
            raise TypeError(
                "{}: from must start with ./ for local pkgs: {}"
                .format(pkg_req, from_))
        if isinstance(pkg_req, str):
            pkg_req = PkgReq.from_str(pkg_req)
        self.pkg_req = pkg_req
        self.from_ = from_
        self.full = full

    @classmethod
    def from_dict(cls, dct):
        assert is_pkg(dct)
        assert is_unresolved(dct)

        return cls(
            pkg_req=dct['pkgReq'],
            from_=dct['from'],
            full=dct,
        )

    def to_dict(self):
        return {
            F_STATE: S_UNRESOLVED,
            'pkgReq': self.pkg_req,
            'from': self.from_,
        }

    def is_unresolved(self):
        return True

    def is_from_local(self):
        return isinstance(self.from_, str)

class PkgConfig(object):
    def __init__(self, base):
        self.base = abspath(base)
        self.pkg_root = pjoin(self.base, FILE_PKG)
        self.wakedir = pjoin(self.base, ".wake")
        self.pkg_fingerprint = pjoin(self.wakedir, FILE_FINGERPRINT)
        self.path_local_deps = pjoin(self.wakedir, FILE_LOCAL_DEPENDENCIES)

    def init_wakedir(self):
        assert path.exists(self.base)
        assert path.exists(self.pkg_root)
        os.makedirs(self.wakedir, exist_ok=True)

    def get_current_fingerprint(self):
        if not path.exists(self.pkg_fingerprint):
            return None
        return jsonloadf(self.pkg_fingerprint)

    def path_abs(self, relpath):
        return pjoin(self.base, relpath)

    def paths_abs(self, relpaths):
        return map(self.path_abs, relpaths)

    def __repr__(self):
        return "PkgConfig({})".format(self.base)
