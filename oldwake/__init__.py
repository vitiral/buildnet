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

import os

from .utils import *
from . import pkg as mpkg
from . import store as mstore
from . import hash as mhash


class Config(object):
    def __init__(self):
        self.user_path = abspath(os.getenv("WAKEPATH", "~/.wake"))
        self.base = os.getcwd()

        root_config = mpkg.PkgConfig(self.base)
        self.pkgs_locked = pjoin(root_config.wakedir, "pkgsLocked.json")
        self.pkgs_defined = pjoin(root_config.wakedir, "pkgsDefined.jsonnet")
        self.run = pjoin(root_config.wakedir, "run.jsonnet")

        user_file = pjoin(self.user_path, "user.jsonnet")
        if not path.exists(user_file):
            fail("must instantiate user credentials: " + user_file)
        self.user = manifest_jsonnet(user_file)

        self.store = mstore.Store(
            self.base,
            pjoin(self.user_path, self.user.get('store', 'store')),
        )

    def init(self):
        self.store.init_store()

    def remove_caches(self):
        self.store.remove_store()

    def run_pkg(self, pkg_config, locked=None):
        locked = {} if locked is None else locked

        runtxt = RUN_TEMPLATE.format(
            wakelib=wakelib,
            pkgs_defined=self.pkgs_defined,
            pkg_root=pkg_config.pkg_root,
        )

        self.create_defined_pkgs(locked)
        dumpf(self.run, runtxt)
        manifest = manifest_jsonnet(self.run)
        return mpkg.PkgManifest.from_dict(manifest)

    def compute_pkg_fingerprint(self, pkg_config):
        root = self.run_pkg(pkg_config).root

        hashstuff = mhash.HashStuff(pkg_config.base)
        if path.exists(pkg_config.path_local_deps):
            hashstuff.update_file(pkg_config.path_local_deps)

        hashstuff.update_file(pkg_config.pkg_root)
        hashstuff.update_paths(pkg_config.paths_abs(root.paths))
        hashstuff.update_paths(pkg_config.paths_abs(root.paths_def))
        return mpkg.Fingerprint(hash_=hashstuff.reduce(),
                                hash_type=hashstuff.hash_type)

    def assert_fingerprint_matches(self, pkg_config):
        fingerprint = pkg_config.get_current_fingerprint()
        computed = self.compute_pkg_fingerprint(pkg_config)

        if fingerprint != computed:
            raise ValueError(
                "fingerprints do no match:\nfingerprint.json={}\ncomputed={}".
                format(
                    fingerprint,
                    computed,
                ))

    def dump_pkg_fingerprint(self, pkg_config):
        dumpf(pkg_config.pkg_fingerprint,
              '{"hash": "--fake hash--", "hashType": "fake"}')
        fingerprint = self.compute_pkg_fingerprint(pkg_config)
        jsondumpf(pkg_config.pkg_fingerprint, fingerprint.to_dict(), indent=4)
        return fingerprint

    def handle_unresolved_pkg(self, pkg, locked):
        from_ = pkg.from_
        using_pkg = pkg.using_pkg

        if pkg.is_from_local():
            # It is a path, it must _already_ be in the store
            out = self.store.get_pkg_path(pkg.pkg_req, def_okay=True)
            # TODO: to do this, I need the proper req tree
            # if out is None:
            #     raise ValueError("{} was not in the store".format(pkg))
            return out
        else:
            self.exec_get_pkg(pkg, locked)

    def exec_get_pkg(self, pkg, locked):
        # TODO: these should be collected and called all at once.

        get_exec = pkg.exec_

        cmd = {
            F_TYPE: C_READ_PKGS,
            'definitionOnly': True,
            'pkgVersions': [str(pkg.pkg_req)],
        }

        exec_path = pjoin(
            self.store.get_pkg_path(get_exec.path_ref.pkg_ver),
            get_exec.path_ref.path,
        )

        run_dir = self.store.get_retrieval_dir()
        result = subprocess.run(
            [exec_path],
            input=json.dumps(cmd).encode(),
            cwd=run_dir,
            stderr=subprocess.PIPE,
        )

        print("retreiving pkg {} into {}".format(str(pkg.pkg_req), run_dir))
        if result.returncode != 0:
            raise RuntimeError("Failed: " + result.stderr.decode())

        retrieved = path.join(run_dir, DIR_WAKE, DIR_RETRIEVED)
        for pdir in os.listdir(retrieved):
            pkg_path = os.path.join(retrieved, pdir)
            ret_config = mpkg.PkgConfig(pkg_path)

            if not os.path.exists(ret_config.wakedir):
                os.mkdir(ret_config.wakedir)
            if not os.path.exists(ret_config.path_local_deps):
                jsondumpf(ret_config.path_local_deps, {})

            self.dump_pkg_fingerprint(ret_config)
            simple_pkg = self.run_pkg(ret_config).root
            self.store.add_pkg(ret_config, simple_pkg)

            # TODO: version resolution should happen before this is done.
            locked[simple_pkg.get_pkg_key()] = simple_pkg.pkg_ver

    def create_defined_pkgs(self, locked):
        with open(self.pkgs_defined, 'w') as fd:
            fd.write("{\n")
            for pkg_key, pkg_ver in locked.items():
                line = "  \"{}\": import \"{}/{}\",\n".format(
                    pkg_key,
                    self.store.get_pkg_path(pkg_ver),
                    FILE_PKG,
                )
                fd.write(line)
            fd.write("}\n")
            os.fsync(fd)


## COMMANDS AND MAIN


def run_cycle(config, root_config, locked):
    """Run a cycle with the config and root_config at the current setting."""
    manifest = config.run_pkg(root_config, locked)

    num_unresolved = 0
    for pkg in manifest.all:
        if isinstance(pkg, mpkg.PkgUnresolved):
            num_unresolved += 1
            config.handle_unresolved_pkg(pkg, locked)

    return (num_unresolved, manifest)


def store_local(config, local_abs, locked):
    """Recursively traverse local dependencies, putting them in the store.

    Also stores own version in the lockfile.
    """
    local_config = mpkg.PkgConfig(local_abs)
    if not path.exists(local_config.pkg_fingerprint):
        jsondumpf(
            local_config.pkg_fingerprint,
            mpkg.Fingerprint('fake', 'fake').to_dict(),
        )

    local_manifest = config.run_pkg(local_config)
    local_pkg = local_manifest.root
    local_key = local_pkg.get_pkg_key()
    if local_key in locked:
        raise ValueError(
            "Attempted to add {} to local overrides twice.".format(local_key))

    # recursively store all local dependencies first
    deps = {}
    for dep in local_manifest.all:
        if dep.is_unresolved() and dep.is_from_local():
            deps[dep.from_] = store_local(
                config,
                pjoin(local_abs, dep.from_),
                locked,
            ).pkg_ver

    deps = OrderedDict(sorted(deps.items()))
    jsondumpf(local_config.path_local_deps, deps)
    config.dump_pkg_fingerprint(local_config)

    local_pkg = config.run_pkg(local_config).root
    if local_key in locked:
        raise ValueError(
            "Attempted to add {} to local overrides twice.".format(local_key))
    locked[local_key] = local_pkg.pkg_ver
    config.store.add_pkg(
        local_config,
        # Note: we don't pass deps here because we only care about hashes
        local_pkg,
        local=True,
    )

    return local_pkg


def build(args):
    config = Config()
    print("## building local pkg {}".format(config.base))
    root_config = mpkg.PkgConfig(config.base)

    print("-> initializing the global cache")
    if is_debug():
        config.remove_caches()
    root_config.init_wakedir()
    config.init()

    print("-> recomputing fingerprint")
    # TODO: this needs to be reworked. The solution also solves pkg overrides!
    # - Compute the hash of this pkg, by traversing all local dependencies
    #   first and computing their hashes
    # - When a local pkg's hash has been computed, put it in the `store.localPkgs`.
    #   This is a special place in the store that overrides pkgs for _only this
    #   directory_. (It is actually located in .wake/store/localPkgs). Also, the
    #   pkg names there don't include the hash (will be overriden if hash changes)
    # - This goes all the way down, until the rootPkg's hash has been computed and
    #   is stored in the local store.
    # - When retieving pkgs, we first check if the VERSION is in the local store.
    #   if it is, we take it.
    locked = {}
    store_local(config, config.base, locked)

    print("## BUILD CYCLES")

    cycle = 0
    unresolved = -1
    while unresolved:
        print("### CYCLE={}".format(cycle))
        print("-> locked pkgs")
        pp(locked)
        # TODO: run in loop
        new_unresolved, manifest = run_cycle(config, root_config, locked)

        print("-> manifest below. unresolved={}".format(new_unresolved))
        pp(manifest.to_dict())

        if unresolved == new_unresolved:
            fail("deadlock detected: unresolved has not changed for a cycle")
        unresolved = new_unresolved
        cycle += 1


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description='Wake: the pkg manager and build system of the web', )

    subparsers = parser.add_subparsers(help='[sub-command] help')
    parser_build = subparsers.add_parser(
        'build', help='build the pkg in the current directory')
    parser_build.set_defaults(func=build)

    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv[1:])

    print(args)
    args.func(args)
