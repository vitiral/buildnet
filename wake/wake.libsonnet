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

local C = (import 'wakeConstants.json');

C {
    local wake = self
    ,
    local U = wake.util
    ,
    local _P = wake._private

    ,
    # The package's namespace and name.
    pkgName(namespace, name):
        local namespaceStr = U.stringDefault(namespace);
        local namespaceLen = std.length(namespaceStr);

        assert namespaceLen == 0 || namespaceLen > 3 : 'namespace length must be > 3';
        assert !U.hasSep(namespaceStr) : "namespace must not contain '#'";
        assert std.length(name) > 3 : 'name length must be > 3';
        assert !U.hasSep(name) : "name must not contain '#'";

        std.join(C.WAKE_SEP, [
            namespaceStr,
            name,
        ])

    ,
    # Specifies what versions of a package are required using a semver.
    pkgReq(namespace, name, semver=null): {
        local semverStr = U.stringDefault(semver),

        assert !U.hasSep(semverStr) : "semver must not contain '@'",

        result: std.join(C.WAKE_SEP, [
            wake.pkgName(namespace, name),
            semverStr,
        ]),
    }.result

    ,
    # An exact version of a pkgName, including the digest.
    pkgVer(namespace, name, version, digest):
        assert std.isString(digest) : 'digest must be a string';
        # Note: the version must be an exact semver, but is checked later.
        std.join(C.WAKE_SEP, [
            wake.pkgName(namespace, name),
            version,
            digest,
        ])

    ,
    # Declare a pkg (in PKG.libsonnet)
    pkg(
        pkgVer,

        # Description and other metadata regarding the origin of the package.
        pkgOrigin=null,

        # Local paths (files or dirs) this pkg depends on for building.
        paths=null,

        # packages that this pkg depends on.
        deps=null,

        # Function which returns the export of this pkg.
        export=null,
    ): {
        [C.F_TYPE]: C.T_PKG,
        [C.F_STATE]: C.S_DECLARED,
        pkgVer: pkgVer,
        pkgOrigin: pkgOrigin,
        paths: U.arrayDefault(paths),
        deps: U.objDefault(deps),

        # lazy functions
        export: export,
    }

    ,
    # Convert a pkg object into only it's digest elements.
    pkgDigest(pkg): {
        [k]: pkg[k]
        for k in std.objectFields(pkg)
        if k != 'export'
    }

    ,
    # Declare dependencies for a package.
    deps(
        unrestricted=null,
        restricted=null,
        restrictedMajor=null,
        restrictedMinor=null,
        global=null,
    ): {
        [C.F_TYPE]: C.T_DEPS,
        unrestricted: U.objDefault(unrestricted),
        restricted: U.objDefault(restricted),
        restrictedMajor: U.objDefault(restrictedMajor),
        restrictedMinor: U.objDefault(restrictedMinor),
        global: U.objDefault(global),
    }

    ,
    # Declare how to build a module.
    module(
        pkg,
        modules,
        reqFsEntries=null,
        export=null,
        exec=null,
        origin=null,
    ): null  # TODO

    ,
    # Reference a path from within a pkg or module.
    pathRef(
        # A pkg or module to reference.
        ref,

        # The local path within the ref
        path,
    ): {
        assert U.isAtLeastDefined(ref) : 'ref must be defined',

        local vals = if U.isPkg(ref) then
            { type: C.T_PATH_REF_PKG, id: ref.pkgVer }
        else
            assert false : 'ref must be a pkg or a module.';
            null,

        [C.F_TYPE]: vals.type,
        [C.F_STATE]: C.S_DEFINED,
        [if U.isPkg(ref) then 'pkgVer' else 'modVer']: vals.id,
        path: path,
    }

    ,
    # Specify an executable from within a pkg and container.
    exec(
        # is not necessarily the exec's
        # is determined by the container.
        pathRef,

        # or pkg should be executed, or
        # executed "anywhere."
        # must == `wake.LOCAL_CONTAINER`
        container,

        # List of strings to pass as arguments to the executable.
        params=null,
    ): {
        [C.F_TYPE]: C.T_EXEC,
        [C.F_STATE]: C.S_DEFINED,

        assert U.isPathRef(pathRef) : 'pathRef is wrong type',
        assert container == C.EXEC_LOCAL || U.isExecLocal(container) :
               'container must == EXEC_LOCAL or a container which is EXEC_LOCAL',

        pathRef: pathRef,
        container: container,
        params: U.defaultObj(params),
    }

    ,
    # An error object. Will cause build to fail.
    err(msg): {
        [C.F_TYPE]: C.T_ERROR,
        msg: msg,
    }


    ,
    _private: {
        local P = self

        ,
        # Looks up all items in the dependency tree
        lookupDeps(requestingPkgVer, deps):
            # Looks up the pkgReq based on who's asking.
            local lookupPkg = function(requestingPkgVer, category, pkgReq)
                local pkgKey = std.join(C.WAKE_SEP, [
                    requestingPkgVer,
                    pkgReq,
                ]);

                # !! NOTE: wake._private.pkgsDefined is **injected** by
                # !! wake/runWakeExport.jsonnet
                assert pkgKey in P.pkgsDefined :
                       '%s requested %s (in %s) but it does not exist in the store' % [
                    requestingPkgVer,
                    pkgReq,
                    category,
                ];

                P.pkgsDefined[pkgKey];

            # Lookup all packages in deps
            local lookupPkgs = function(category, depPkgs) {
                [k]: lookupPkg(requestingPkgVer, category, depPkgs[k])
                for k in std.objectFields(depPkgs)
            };

            # Return the looked up dependencies
            {
                unrestricted: lookupPkgs('unrestricted', deps.unrestricted),
                restricted: lookupPkgs('restricted', deps.restricted),
                restrictedMajor: lookupPkgs('restrictedMajor', deps.restrictedMajor),
                restrictedMinor: lookupPkgs('restrictedMinor', deps.restrictedMinor),
                global: lookupPkgs('global', deps.global),
            }

        ,
        recurseCallExport(wake, pkg):
            local fnDeps = P.lookupDeps(pkg.pkgVer, pkg.deps);
            local callPkgsExport = function(pkgs) {
                [k]: P.recurseCallExport(wake, pkgs[k])
                for k in std.objectFields(pkgs)
            };
            assert fnDeps != null: "fnDeps is null";
            {
                local this = self,

                # straight copy of pkg
                [C.F_TYPE]: pkg[C.F_TYPE],
                [C.F_STATE]: C.S_DEFINED,
                pkgVer: pkg.pkgVer,
                pkgOrigin: pkg.pkgOrigin,
                paths: pkg.paths,


                # Recursively resolve all dependencies
                deps: {
                    [k]: callPkgsExport(fnDeps[k])
                    for k in std.objectFields(fnDeps)
                },

                # Use the reference which includes resolved dependencies
                export: pkg.export(wake, this),
            }

        # , simplify(pkg): {
        #     [C.F_TYPE]: pkg[C.F_TYPE],
        #     [C.F_STATE]: pkg[C.F_STATE],
        #     pkgVer: pkg.pkgVer,

        #     local getIdOrUnresolved = function(dep)
        #         if U.isUnresolved(dep) then
        #             dep
        #         else
        #             dep.pkgVer,

        #     pathsDef: pkg.pathsDef,
        #     paths: pkg.paths,
        #     # FIXME: pathsReq
        #     pkgs: {
        #         [dep]: getIdOrUnresolved(pkg.pkgs[dep])
        #         for dep in std.objectFields(pkg.pkgs)
        #     },
        #     export: pkg.export,
        # }

        # , recurseSimplify(pkg):
        #     if U.isUnresolved(pkg) then
        #         [pkg]
        #     else
        #         local simpleDeps = [
        #             P.recurseSimplify(pkg.pkgs[dep])
        #             for dep in std.objectFields(pkg.pkgs)
        #         ];
        #         [P.simplify(pkg)] + std.flattenArrays(simpleDeps)
    }

    ,
    util: {
        # Wake typecheck functions
        isWakeObject(obj):
            std.isObject(obj)
            && (C.F_TYPE in obj)

        ,
        isErr(obj):
            U.isWakeObject(obj) && obj[C.F_TYPE] == C.T_ERR

        ,
        isPkg(obj):
            U.isWakeObject(obj) && obj[C.F_TYPE] == C.T_PKG

        ,
        # Wake status-check functions.
        isUnresolved(obj):
            U.isWakeObject(obj)
            && obj[C.F_STATE] == C.S_UNRESOLVED

        ,
        isDeclared(obj):
            U.isWakeObject(obj)
            && obj[C.F_STATE] == C.S_DECLARED

        ,
        isDefined(obj):
            U.isWakeObject(obj)
            && obj[C.F_STATE] == C.S_DEFINED

        ,
        isAtLeastDefined(obj):
            U.isDefined(obj)

        ,
        isPathRef(obj):
            U.isWakeObject(obj) && (
                obj[C.F_TYPE] == C.T_PATH_REF_PKG
                || obj[C.F_TYPE] == C.T_PATH_REF_MODULE
            )

        ,
        isExec(obj):
            U.isWakeObject(obj)
            && obj[C.F_TYPE] == C.T_EXEC

        ,
        isExecLocal(obj):
            U.isExec(obj) && obj.container == C.EXEC_LOCAL

        ,
        hasSep(s): U.containsChr(C.WAKE_SEP, s)

        ,
        # General Helpers
        boolToInt(bool): if bool then 1 else 0
        ,
        containsChr(c, str): !(std.length(std.splitLimit(str, c, 1)) == 1)

        ,
        # Retrieve a value from an object at an arbitrary depth.
        getKeys(obj, keys, cur_index=0):
            local value = obj[keys[cur_index]];
            local new_index = cur_index + 1;
            if new_index == std.length(keys) then
                value
            else
                U.getKeys(value, keys, new_index)

        ,
        # Default functions return empty containers on null
        arrayDefault(arr): if arr == null then [] else arr
        ,
        objDefault(obj): if obj == null then {} else obj
        ,
        stringDefault(s): if s == null then '' else s,
    },
}
