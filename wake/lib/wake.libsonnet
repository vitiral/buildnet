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

(import "wakeConstants.json") + {
    local wake = self,
    local U = wake.util,

    // (#SPC-api.pkgId): The exact id of a pkg.
    //
    // This is similar to pkgReq except it is the _exact_ pkg, with the hash
    // included in the Id.
    pkgId(name, version, namespace, hash):
        assert std.isString(hash) : "hash must be string";
        // Note: the version must be an exact semver, but is checked later.
        "%s,%s" % [
            wake.pkgReq(name, version, namespace),
            hash,
        ],

    // (#SPC-api.pkgReq): a pkg requirement with a semantic version.
    //
    // This is used as (partof) the filepath for pkgs and modules.
    //
    // Errors:
    // - name and namespace must be length > 3
    // - It is an error for any field to have commas.
    // - versionReq must be a valid semverReq
    pkgReq(
        // The name of the pkgReq.
        name,

        // The version requirements of the pkgReq.
        //
        // wake will attempt to match the requirements, taking
        // into account other pkgs to use as few pkgs as possible.
        versionReq=null,

        // The namespace to find the pkg.
        namespace=null
    ): {
        local versionStr = U.stringDefault(versionReq),
        local namespaceStr = U.stringDefault(namespace),
        local namespaceLen = std.length(namespaceStr),
        local hasComma = function(s) U.containsChr(',', s),

        assert std.length(name) > 3: "name length must be > 3",
        assert namespaceLen == 0 || namespaceLen > 3: "namespace length must be > 3",
        assert !hasComma(name): "name must not contain ','",
        assert !hasComma(versionStr): "versionReq must not contain ','",
        assert !hasComma(namespaceStr): "namespace must not contain ','",

        result: '%s,%s,%s' %[
            name,
            versionStr,
            namespaceStr,
        ],
    }.result,

    // (#SPC-api.getPkg): retrieve a pkg lazily.
    getPkg(
        // The pkgReq(...) to retrieve.
        pkgReq,

        // A local path (string) or `exec` to use for retrieving the path.
        from=null
    ):
        # TODO: check in completePkgs first
        local pkgsDefined = wake._private.pkgsDefined;
        local pkgCompletes = wake._private.pkgCompletes;

        if pkgReq in pkgsDefined then
            // TODO: must keep track of all ways we got the pkg
            local pkgFn = pkgsDefined[pkgReq];
            pkgFn(wake)
        else
            wake._private.unresolvedPkg(pkgReq, from),

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

        // The name of the pkg.
        //
        // Type: string
        name,

        // The exact version of the pkg.
        //
        // Type: string
        version,

        // the (optional) namespace of the pkg.
        //
        // Type: string
        namespace=null,

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
        defPaths=null,

        // Local paths (files or dirs) this pkg depends on for building.
        //
        // These are included when the full pkg is retrieved or setup in
        // a sandbox.
        //
        // Type: list[string]
        paths=null,

        // pkgs that this pkg depends on.
        //
        // Type: object of key/getPkg(...) pairs
        pkgs=null,

        // Exports of this pkg.
        //
        // Called once the pkg has been fully defined (all dependencies resolved, etc).
        //
        // Type: function(wake, pkgDefined) -> Object
        exports=null,
    ): {
        [wake.F_TYPE]: wake.T_PKG,
        [wake.F_STATE]: wake.S_DECLARED,
        fingerprint: fingerprint,
        name: name,
        version: version,
        namespace: U.stringDefault(namespace),
        pkgId: wake.pkgId(name, version, namespace, fingerprint.hash),

        defPaths: U.arrayDefault(defPaths),
        paths: U.arrayDefault(paths),
        pkgs: U.objDefault(pkgs),
        exports: exports,
    },

    // (#SPC-api.declareModule): declare how to build something with a pkg.
    //
    // Modules are included in `pkg.exports`, as they are tied to the pkg.
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

        // (lazy) The primary `exec` object used for building this module.
        //
        // Type `function(wake, module) -> wake.exec(...)`
        exec=null,

        // The origin of the module, such as author, license, etc
        origin=null,
    ): null, // TODO

    // (#SPC-api.fsentry): Specify a file system object within a pkg or module.
    //
    // `fsentry` is an object which specifies a file or a directory.
    //
    // - `from=pkg` or `from=module` acts as a reference to a file at `path` that
    //   is local to the pkg or built by the module, so that dependent objects
    //   can include references to them in their container.
    // - `from=fsentryRef` can be used in `pkg.reqFiles` to specify that a file
    //   needs to be linked from `fsentryRef.pkg.pkgId/$path` to `./path` of
    //   the dependent module.
    //
    // As a demonstration, if you wanted to link a file within your own pkg,
    // you could write:
    //
    // ```
    // local data_txt = "./data.txt",
    // declarePkg(
    //     ...,
    //     files=[data_txt],
    //     reqFiles=function(wake, pkg) [
    //         wake.fsentry(
    //             "linked-data.txt",
    //             from=wake.fsentry(data_txt, from=pkg)
    //         ),
    //     ],
    // )
    // ```
    fsentry(
        // The local path to the resulting file or directory.
        path,

        // A pkg or another fsentry.
        from,
    ),

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
    exec(
        // The pkg to execute within. Should be a pkg or a module.
        within,

        // The path to execute within the given pkg or module.
        //
        // Type: string to local or linked path
        path,

        // A `exec` (with `container=wake.LOCAL`) to specify _where_ the
        // module or pkg should be executed.
        container,

        // Config object to manifest and store in .wake/config.json
        //
        // Type: arbitrary manifestable value
        config=null,

        // List of strings to pass as arguments to the executable.
        //
        // Type: list[string]
        args=null,

        // Environment variables to pass to the executable. Must be an object of strings
        // for the keys and values.
        //
        // Consider using `config` instead.
        env=null,
    ): null, // TODO


    _private: {
        local P = self,

        unresolvedPkg(pkgReq, from):  {
            [wake.F_TYPE]: wake.T_PKG,
            [wake.F_STATE]: wake.S_UNRESOLVED,
            pkgReq: pkgReq,
            from: from,
        },

        // Used to lazily define the exports of the pkg and sub-pkgs.
        recurseDefinePkg(wake, pkg): {
            local this = self,
            local _ = std.trace("recurseDefinePkg in " + pkg.pkgId, null),
            local recurseMaybe = function(depPkg)
                if U.isUnresolved(depPkg) then
                    depPkg
                else
                    P.recurseDefinePkg(wake, depPkg),

            returnPkg: pkg + {
                [wake.F_STATE]: if P.hasBeenDefined(pkg, this.returnPkg) then
                    wake.S_DEFINED else pkg[wake.F_STATE],

                exports:
                    local out = pkg.exports(wake, this.returnPkg);
                    assert std.isObject(out)
                        : "%s exports did not return an object"
                        % [this.returnPkg.pkgId];
                    out,

                pkgs: {
                    [dep]: recurseMaybe(pkg.pkgs[dep])
                    for dep in std.objectFields(pkg.pkgs)
                },
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
                pkg
            else
                local simpleDeps = [
                    P.recurseSimplify(pkg.pkgs[dep])
                    for dep in std.objectFields(pkg.pkgs)
                ];
                [P.simplify(pkg)] + simpleDeps,

        simplify(pkg): {
            [wake.F_TYPE]: pkg[wake.F_TYPE],
            [wake.F_STATE]: pkg[wake.F_STATE],
            pkgId: pkg.pkgId,
            name: pkg.name,
            version: pkg.version,
            namespace: pkg.namespace,
            fingerprint: pkg.fingerprint,

            local onlyIdOrUnresolved = function(dep)
                if U.isUnresolved(dep) then
                    dep
                else
                    dep.pkgId,

            defPaths: pkg.defPaths,
            paths: pkg.paths,
            pkgs: {
                [dep]: onlyIdOrUnresolved(pkg.pkgs[dep])
                for dep in std.objectFields(pkg.pkgs)
            },
            exports: pkg.exports,
        },
    },

    util: {
        // Wake typecheck functions
        isWakeObject(obj):
            std.isObject(obj)
            && (wake.F_TYPE in obj),
        isPkg(obj):
             U.isWakeObject(obj) && obj[wake.F_TYPE] == wake.T_PKG,

        // Wake status-check functions.
        isUnresolved(obj):
            assert U.isWakeObject(obj) : "value must be a wake object";
            obj[wake.F_STATE] == wake.S_UNRESOLVED,

        isDefined(obj):
            assert U.isWakeObject(obj) : "value must be a wake object";
            obj[wake.F_STATE] == wake.S_DEFINED,

        // General Helpers
        boolToInt(bool): if bool then 1 else 0,
        containsChr(c, str): !(std.length(std.splitLimit(str, c, 1)) == 1),
        isVersionSingle(ver): {
            local arr = ver.split(ver, '.')
        },

        // Default functions return empty containers on null
        arrayDefault(arr): if arr == null then [] else arr,
        objDefault(obj): if obj == null then {} else obj,
        stringDefault(s): if s == null then "" else s,
    },
}
