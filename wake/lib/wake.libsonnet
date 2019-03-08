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

local C = import "wakeConstants.json";

C + {
    local wake = self,
    local U = wake.util,
    local _P = wake._private,

    // (#SPC-api.pkgId): The exact id of a pkg.
    //
    // This is similar to pkgReq except it is the _exact_ pkg, with the hash
    // included in the Id.
    pkgId(namespace, name, version, hash):
        assert std.isString(hash) : "hash must be string";
        // Note: the version must be an exact semver, but is checked later.
        std.join(C.WAKE_SEP, [
            wake.pkgReq(namespace, name, version),
            hash,
        ]),

    // (#SPC-api.pkgReq): a pkg requirement with a semantic version.
    //
    // This is used as (partof) the filepath for pkgs and modules.
    //
    // Errors:
    // - name and namespace must be length > 3
    // - It is an error for any field to have commas.
    // - versionReq must be a valid semverReq
    pkgReq(
        // The namespace to find the pkg.
        namespace,

        // The name of the pkg.
        name,

        // The version requirements of the pkgReq.
        //
        // wake will attempt to match the requirements, taking
        // into account other pkgs to use as few pkgs as possible.
        versionReq=null,

    ): {
        local versionStr = U.stringDefault(versionReq),

        assert !_P.hasSep(versionStr): "versionReq must not contain '#'",

        result: std.join(C.WAKE_SEP, [
            wake.pkgKey(namespace, name),
            versionStr,
        ]),
    }.result,


    // A more generalized version of the pkg. Used when looking up pkgs from
    // locked packages.
    pkgKey(namespace, name):
        local namespaceStr = U.stringDefault(namespace);
        local namespaceLen = std.length(namespaceStr);

        assert namespaceLen == 0 || namespaceLen > 3: "namespace length must be > 3";
        assert !_P.hasSep(namespaceStr): "namespace must not contain '#'";
        assert std.length(name) > 3: "name length must be > 3";
        assert !_P.hasSep(name): "name must not contain '#'";

        std.join(C.WAKE_SEP, [
            namespaceStr,
            name,
        ]),

    // Lazily retrieve an export from a pkg, waiting until the pkg is defined.
    //
    // `keys` is either a string or an array of strings. `keys=['a', 'b']` will retrieve
    // `pkg.exports['a']['b']`.
    getExport(pkg, key): {
        [C.F_TYPE]: C.T_GET_EXPORT,
        [C.F_STATE]: C.S_DECLARED,

        assert U.isPkg(pkg) : "can only lazily retrieve exports from a pkg",
        assert std.isString(key) : "key must be a string",

        pkg: pkg,
        key: key,
    },

    // (#SPC-api.getPkg): retrieve a pkg lazily.
    getPkg(
        // The pkgReq(...) to retrieve.
        pkgReq,

        // A local path (string) or `exec` to use for retrieving the path.
        from=null
    ):
        local pkgKey = _P.getPkgKey(pkgReq);
        # TODO: check in pkgsComplete first
        if pkgKey in _P.pkgsDefined then
            // TODO: must keep track of all ways we got the pkg
            local pkgFn = _P.pkgsDefined[pkgKey];
            pkgFn(wake)
        else
            _P.unresolvedPkg(pkgReq, from),

    // (#SPC-api.declarePkg): declare a pkg.
    //
    // Must be the only return of the function in PKG.libsonnet of the form
    //
    // ```
    // function(wake)
    //    wake.declarePkg(
    //        fingerprint=import "./.wake/fingerprint.json",
    //        name="mypkg",
    //        version="1.0.0",
    //        # ... etc
    //    )
    // ```
    declarePkg(
        // The fingerprint, **imported** from .wake/fingerprint.json
        fingerprint,

        // the (optional) namespace of the pkg.
        //
        // Type: string
        namespace,

        // The name of the pkg.
        //
        // Type: string
        name,

        // The exact version of the pkg.
        //
        // Type: string
        version,

        // General description of the pkg, for humans to read.
        // Type: string
        description=null,

        // Local paths (files or dirs) this pkg depends on for building.
        //
        // These are included when the full pkg is retrieved or setup in
        // a sandbox.
        //
        // Type: list[string]
        paths=null,

        // Local paths (files or dirs) this pkg depends on for its definition.
        //
        // Paths used in the "define" phase must be included in this list.
        // Typically will just be items this PKG.libsonnet imports in some way.
        // This should be kept to a minimal size so that it can be retrieved
        // quickly.
        //
        // Note that .wake.libsonnet and PKG.libsonnet are automatically
        // included in this list.
        //
        // Type: list[string]
        pathsDef=null,

        // pkgs that this pkg depends on.
        //
        // Type: object of key/getPkg(...) pairs
        pkgs=null,

        // Exports of this pkg.
        //
        // > Called once the pkg has been fully defined (all dependencies resolved, etc).
        //
        // Type: function(wake, pkgDefined) -> Object
        exports=null,
    ): {
        [C.F_TYPE]: C.T_PKG,
        [C.F_STATE]: C.S_DECLARED,
        fingerprint: fingerprint,
        namespace: U.stringDefault(namespace),
        name: name,
        version: version,
        description: description,
        pkgId: wake.pkgId(namespace, name, version, fingerprint.hash),
        paths: U.arrayDefault(paths),
        pathsDef: U.arrayDefault(pathsDef),
        pkgs: U.objDefault(pkgs),

        # lazy functions
        exports: exports,
    },

    // (#SPC-api.declareModule): declare how to build something.
    //
    // Modules are included in `pkg.exports`, as they are always tied to a pkg.
    // It is allowed for a pkg to export another pkg's modules (meta modules).
    //
    // Note that when `exec` is running it is within its `container` and has read
    // access to all files and inputs the local `pkg` the module is defined in, as
    // well as any pkgs and modules it is dependt on.
    declareModule(
        // The pkg this module is defined in.
        pkg,

        // Module objects this module depends on.
        modules,

        // (lazy) Additional required `fsentry`s (files or dirs)
        //
        // Type: `function(wake, pkg, moduleDef) -> list[fsentry]`
        reqFsEntries=null,

        // function which behaves identically to `pkg.exports`.
        //
        // Contains a key/value map of the objects exported by this module.
        // Must not contain any unresolved objects (unresolved objects will
        // never be resolved).
        exports=null,

        // (lazy) The `exec` object used for building this module.
        //
        // Type `function(wake, module) -> wake.exec(...)`
        exec=null,

        // The origin of the module, such as author, license, etc
        origin=null,
    ): null, // TODO

    // (#SPC-api.pathRef): Reference a path from within a pkg or module.
    //
    // This is used by `exec` to declare exactly which file to execute,
    // but it is also the standard way to "export" files for other packages and
    // modules to use.
    //
    // Returns: pathRefPkg or pathRefModule
    pathRef(
        // A pkg or module to reference.
        ref,

        // The local path within the ref
        path,
    ): {
        assert U.isAtLeastDefined(ref) : "ref must be at least defined",

        local vals = if U.isPkg(ref) then
            {type: C.T_PATH_REF_PKG, id: ref['pkgId']}
        else
            assert false : "ref must be a pkg or a module.";
            null,

        [C.F_TYPE]: vals.type,
        [C.F_STATE]: C.S_DEFINED,
        [if U.isPkg(ref) then 'pkgId' else "moduleId"]: vals.id,
        path: path,
    },

    // (#SPC-api.exec): specify an executable from within a pkg and container.
    //
    // Where other pkg managers or build systems might have "hooks" or "plugins", wake
    // has `exec`. Exec is a fully flexible specification on how to execute something.
    // You sepcify what _files_ are available via `within` (a pkg or module) and you
    // specify _where_ the execution happens with `container`. Finally you specify
    // the exact arguments to use.
    //
    // Exec is not executed directly. It is manifested as json and passed to
    // the specified container, which performs the actual exection. Therefore it
    // is perfectly legal to override any of the returned arguments. For instance,
    // a module can include an `exec` in `exports`, and another module can use
    // it with a few overriden params.
    //
    // All values given to `exec` must be immediately manifestable.
    //
    // ## How an `exec` operates.
    //
    // A temporary directory is instantiated by the **store** which contains ONLY
    // a `.wake/` directory containing the following files:
    //
    // - `store`: an executable which follows @SPC-arch.wakeStoreOverride, allowing
    //   the executable to retrieve links to paths, probably according to the config.
    // - `exec.json`: this object directly manifested.
    //
    // If the `container=wake.EXEC_LOCAL` then the `pathRef` is executed directly,
    // with the given env and args.
    //
    // Otherwise, the `container.pathRef` is executed with env `__WAKE_CONTAINER=y`.
    // It is then the job of the container exec to set up the execution environment
    // and run the exec.
    exec(
        // Where the exec is located. Note that this is not necessarily the exec's
        // "environment" (files and folders). That is determined by the container.
        pathRef,

        // A `exec` (itself with `container=wake.LOCAL_CONTAINER`) to specify
        // _where_ the module or pkg should be executed.
        container,

        // Arbitrary config object.
        config=null,

        // List of strings to pass as arguments to the executable.
        //
        // Type: list[string]
        args=null,

        // Environment variables to pass to the executable. Must be an object of strings
        // for the keys and values.
        //
        // Consider using `config` instead.
        //
        // Anything beginning with `__WAKE_` is reserved for use by wake.
        env=null,
    ): {
        [C.F_TYPE]: C.T_EXEC,
        [C.F_STATE]: C.S_DEFINED,

        assert U.isPathRef(pathRef) : "pathRef is wrong type",
        assert container == C.EXEC_LOCAL || U.isExecLocal(container) :
            "container must == EXEC_LOCAL or a container which is EXEC_LOCAL",

        pathRef: pathRef,
        container: container,
        config: config,
        args: U.arrayDefault(args),
        env: U.objDefault(env),
    },

    _private: {
        local P = self,

        unresolvedPkg(pkgReq, from):  {
            [C.F_TYPE]: C.T_PKG,
            [C.F_STATE]: C.S_UNRESOLVED,
            pkgReq: pkgReq,
            from: from,
        },

        // Used to lazily define the exports of the pkg and sub-pkgs.
        recurseDefinePkg(wake, pkg): {
            local this = self,
            local _ = std.trace("recurseDefinePkg in " + pkg.pkgId, null),
            local recurseMaybe = function(depPkg)
                if U.isUnresolved(depPkg) then
                    local from = depPkg.from;
                    if std.isString(from) then
                        depPkg
                    else
                        assert U.isGetExport(from) : "was expecting to be getExport";
                        if U.isDefined(from.pkg) then
                            depPkg + {
                                from: from.pkg.exports[from.key],
                            }
                        else
                            local validFields = {
                                [C.F_TYPE]: null,
                                [C.F_STATE]: null,
                                'pkgId': null,
                                'pkgReq': null,
                            };
                            depPkg + {
                                from: from + {
                                    pkg: {
                                        [field]: from.pkg[field]
                                        for field in std.objectFields(from.pkg)
                                        if field in validFields
                                    },
                                },
                            }
                else
                    P.recurseDefinePkg(wake, depPkg),

            returnPkg: pkg + {
                [C.F_STATE]: if P.hasBeenDefined(pkg, this.returnPkg) then
                    C.S_DEFINED else pkg[C.F_STATE],

                pkgs: {
                    [dep]: recurseMaybe(pkg.pkgs[dep])
                    for dep in std.objectFields(pkg.pkgs)
                },

                exports:
                    if U.isDefined(this.returnPkg) then
                        local out = pkg.exports(wake, this.returnPkg);
                        assert std.isObject(out)
                            : "%s exports did not return an object"
                            % [this.returnPkg.pkgId];
                        out
                    else
                        null,
            }
        }.returnPkg,

        // Return if the newPkg is defined.
        hasBeenDefined(oldPkg, newPkg):
            local definedCount = std.foldl(
                function(prev, v) prev + v,
                [
                    U.boolToInt(U.isDefined(newPkg.pkgs[dep]))
                    for dep in std.objectFields(newPkg.pkgs)
                ],
                0,
            );
            definedCount == std.length(oldPkg.pkgs),

        recurseSimplify(pkg):
            if U.isUnresolved(pkg) then
                [pkg]
            else
                local simpleDeps = [
                    P.recurseSimplify(pkg.pkgs[dep])
                    for dep in std.objectFields(pkg.pkgs)
                ];
                [P.simplify(pkg)] + std.flattenArrays(simpleDeps),

        simplify(pkg): {
            [C.F_TYPE]: pkg[C.F_TYPE],
            [C.F_STATE]: pkg[C.F_STATE],
            pkgId: pkg.pkgId,
            namespace: pkg.namespace,
            name: pkg.name,
            version: pkg.version,
            description: pkg.description,
            fingerprint: pkg.fingerprint,

            local getIdOrUnresolved = function(dep)
                if U.isUnresolved(dep) then
                    dep
                else
                    dep.pkgId,

            pathsDef: pkg.pathsDef,
            paths: pkg.paths,
            # FIXME: pathsReq
            pkgs: {
                [dep]: getIdOrUnresolved(pkg.pkgs[dep])
                for dep in std.objectFields(pkg.pkgs)
            },
            exports: pkg.exports,
        },

        hasSep(s): U.containsChr(C.WAKE_SEP, s),

        getPkgKey(str):
            local items = std.splitLimit(str, C.WAKE_SEP, 3);
            wake.pkgKey(items[0], items[1]),
    },

    util: {
        // Wake typecheck functions
        isWakeObject(obj):
            std.isObject(obj)
            && (C.F_TYPE in obj),

        isPkg(obj):
             U.isWakeObject(obj) && obj[C.F_TYPE] == C.T_PKG,

        isGetExport(obj):
            assert U.isWakeObject(obj): "value must be a wake object";
             U.isWakeObject(obj) && obj[C.F_TYPE] == C.T_GET_EXPORT,

        // Wake status-check functions.
        isUnresolved(obj):
            assert U.isWakeObject(obj) : "value must be a wake object";
            obj[C.F_STATE] == C.S_UNRESOLVED,

        isDeclared(obj):
            assert U.isWakeObject(obj) : "value must be a wake object";
            obj[C.F_STATE] == C.S_DECLARED,

        isDefined(obj):
            assert U.isWakeObject(obj) : "value must be a wake object";
            obj[C.F_STATE] == C.S_DEFINED,

        isAtLeastDefined(obj):
            U.isDefined(obj),

        isPathRef(obj):
             U.isWakeObject(obj) && (
                obj[C.F_TYPE] == C.T_PATH_REF_PKG
                || obj[C.F_TYPE] == C.T_PATH_REF_MODULE),

        isExec(obj):
            assert U.isWakeObject(obj) : "value must be a wake object";
            obj[C.F_TYPE] == C.T_EXEC,

        isExecLocal(obj):
            U.isExec(obj) && obj.container == C.EXEC_LOCAL,

        // General Helpers
        boolToInt(bool): if bool then 1 else 0,
        containsChr(c, str): !(std.length(std.splitLimit(str, c, 1)) == 1),

        // Default functions return empty containers on null
        arrayDefault(arr): if arr == null then [] else arr,
        objDefault(obj): if obj == null then {} else obj,
        stringDefault(s): if s == null then "" else s,
    },
}
